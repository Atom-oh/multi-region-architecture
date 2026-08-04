# ─────────────────────────────────────────────────────────────────────────────
# GitHub Actions OIDC — IAM role for CI/CD workflows
# ─────────────────────────────────────────────────────────────────────────────

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_actions_role ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions" {
  count = var.create_github_actions_role ? 1 : 0
  name  = "github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github[0].arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/*:*"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "github-actions-role"
  })
}

resource "aws_iam_role_policy" "github_actions_ecr_terraform" {
  count = var.create_github_actions_role ? 1 : 0
  name  = "github-actions-ecr-terraform"
  role  = aws_iam_role.github_actions[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    # concat, not a single list: an IAM statement with an empty Resource list is
    # rejected, so the two externally-owned-mgmt statements have to drop out
    # entirely when their name/key list is empty.
    Statement = concat([
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:CreateRepository"
        ]
        Resource = "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.terraform_state_bucket}",
          "arn:aws:s3:::${var.terraform_state_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/${var.terraform_lock_table}"
      }
      ],
      # The eks-az-{a,c} layers read the mgmt cluster live (data "aws_eks_cluster"
      # "mgmt") instead of through its remote state, because that state belongs to
      # AWS-Demo-Platform. That read happens at plan time, so without this grant
      # every plan in those layers fails — including plans that touch nothing else.
      length(var.describable_cluster_names) == 0 ? [] : [{
        Sid      = "DescribeExternallyOwnedMgmtCluster"
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = [for name in var.describable_cluster_names : "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${name}"]
      }],
      # State custody: mgmt's state object lives in this same bucket but is owned
      # and applied by AWS-Demo-Platform. A README warning is not a control — two
      # writers on one state object corrupts it. Deny beats the Allow above.
      # GetObject is in here too: since the spokes read mgmt live
      # (data "aws_eks_cluster" "mgmt") this repo has no remaining reason to read
      # that state, and a state file is the densest secret in the bucket.
      length(var.externally_owned_state_keys) == 0 ? [] : [{
        Sid    = "DenyAccessToExternallyOwnedState"
        Effect = "Deny"
        # Versioned variants are separate actions: the state bucket is versioned,
        # so without them the object could still be read or removed by version id.
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:AbortMultipartUpload",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion"
        ]
        # The key *and* everything under its prefix. TF 1.10+ `use_lockfile` puts
        # the lock in a sibling `<key>.tflock` object and workspaces live under
        # `env:/<name>/<key>` — an exact-key-only Deny leaves both writable, which
        # is the same corruption this statement exists to prevent.
        #
        # `env:/<name>/<key>*` (round-8 review MAJOR, confirmed against diff): the
        # first three patterns all anchor on the bucket-root key, but a workspace
        # object lives under the bucket-root `env:/` prefix instead — none of
        # `${key}`, `${key}*`, `${dirname(key)}/*` match it. Creating a workspace
        # against this key would make this role a second writer on it with none
        # of the three patterns catching it.
        Resource = flatten([
          for key in var.externally_owned_state_keys : [
            "arn:aws:s3:::${var.terraform_state_bucket}/${key}",
            "arn:aws:s3:::${var.terraform_state_bucket}/${key}*",
            "arn:aws:s3:::${var.terraform_state_bucket}/${dirname(key)}/*",
            "arn:aws:s3:::${var.terraform_state_bucket}/env:/*/${key}*",
          ]
        ])
      }],
      # Its own concat element rather than a second object in the list above: this
      # statement carries a Condition and the one above does not, and a tuple of
      # differently-shaped objects fails the ternary's type unification.
      #
      # Denying the object but not its lock row leaves the other half open:
      # deleting the row while AWS-Demo-Platform holds the lock lets a third
      # party apply concurrently, which corrupts the object the statement above
      # protects. LeadingKeys scopes this to those rows — the table is shared with
      # every layer in this repo, so a table-wide Deny would break all of them.
      # Terraform's LockID is "<bucket>/<key>", plus a "-md5" digest row.
      length(var.externally_owned_state_keys) == 0 ? [] : [{
        Sid    = "DenyExternallyOwnedStateLockRows"
        Effect = "Deny"
        # Batch and PartiQL writes reach the same rows under different action names,
        # and LeadingKeys applies to all of them — a Deny listing only the
        # single-item actions is bypassable. (No TransactWriteItems: there is no
        # such IAM action; transactional writes authorize as the item-level actions
        # above, so they are already covered.)
        Action = [
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:PartiQLInsert",
          "dynamodb:PartiQLUpdate",
          "dynamodb:PartiQLDelete"
        ]
        Resource = "arn:aws:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/${var.terraform_lock_table}"
        Condition = {
          "ForAnyValue:StringLike" = {
            # env:/*/<key> rows (round-8 review MAJOR, same workspace gap as the
            # S3 identity Deny above) — a workspace's lock row has the same
            # bucket-root env:/ prefix as its state object.
            "dynamodb:LeadingKeys" = flatten([
              for key in var.externally_owned_state_keys : [
                "${var.terraform_state_bucket}/${key}",
                "${var.terraform_state_bucket}/${key}-md5",
                "${var.terraform_state_bucket}/env:/*/${key}",
                "${var.terraform_state_bucket}/env:/*/${key}-md5",
              ]
            ])
          }
        }
    }])
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# CloudFormation — CDK deployments (aws-fsi-demo etc.)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role_policy" "github_actions_cloudformation" {
  count = var.create_github_actions_role ? 1 : 0
  name  = "github-actions-cloudformation"
  role  = aws_iam_role.github_actions[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudFormationReadDeploy"
        Effect = "Allow"
        Action = [
          "cloudformation:DescribeStacks",
          "cloudformation:DescribeStackEvents",
          "cloudformation:DescribeChangeSet",
          "cloudformation:CreateChangeSet",
          "cloudformation:ExecuteChangeSet",
          "cloudformation:DeleteChangeSet",
          "cloudformation:GetTemplate",
          "cloudformation:GetTemplateSummary",
          "cloudformation:ListStacks"
        ]
        Resource = "arn:aws:cloudformation:*:${data.aws_caller_identity.current.account_id}:stack/*"
      },
      {
        Sid      = "CloudFormationGlobal"
        Effect   = "Allow"
        Action   = ["cloudformation:ListStacks", "cloudformation:GetTemplateSummary"]
        Resource = "*"
      },
      {
        Sid    = "CDKAssetBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::cdk-hnb659fds-assets-${data.aws_caller_identity.current.account_id}-*",
          "arn:aws:s3:::cdk-hnb659fds-assets-${data.aws_caller_identity.current.account_id}-*/*"
        ]
      },
      {
        Sid    = "CDKAssetECR"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:CreateRepository",
          "ecr:SetRepositoryPolicy"
        ]
        Resource = "arn:aws:ecr:*:${data.aws_caller_identity.current.account_id}:repository/cdk-hnb659fds-container-assets-*"
      },
      {
        Sid    = "CDKAssumeRoles"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/cdk-hnb659fds-deploy-role-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/cdk-hnb659fds-file-publishing-role-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/cdk-hnb659fds-image-publishing-role-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/cdk-hnb659fds-lookup-role-*"
        ]
      },
      {
        Sid    = "SSMParameterForCDK"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter"
        ]
        Resource = "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/cdk-bootstrap/*"
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# ECS — Deploy tasks and update services
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role_policy" "github_actions_ecs_deploy" {
  count = var.create_github_actions_role ? 1 : 0
  name  = "github-actions-ecs-deploy"
  role  = aws_iam_role.github_actions[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSTaskDefinition"
        Effect = "Allow"
        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition",
          "ecs:DescribeTaskDefinition",
          "ecs:ListTaskDefinitions"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECSServiceAndTask"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:RunTask",
          "ecs:StopTask"
        ]
        Resource = [
          "arn:aws:ecs:*:${data.aws_caller_identity.current.account_id}:service/*/*",
          "arn:aws:ecs:*:${data.aws_caller_identity.current.account_id}:task/*/*",
          "arn:aws:ecs:*:${data.aws_caller_identity.current.account_id}:cluster/*"
        ]
      },
      {
        Sid    = "ECSDescribeClusters"
        Effect = "Allow"
        Action = [
          "ecs:DescribeClusters",
          "ecs:ListServices"
        ]
        Resource = "arn:aws:ecs:*:${data.aws_caller_identity.current.account_id}:cluster/*"
      },
      {
        Sid      = "PassRoleToECS"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Bedrock — Application Inference Profile for PR review token tracking
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_bedrock_inference_profile" "pr_review" {
  count       = var.create_github_actions_role ? 1 : 0
  name        = "pr-review-sonnet"
  description = "PR review inference profile for CI token tracking"

  model_source {
    copy_from = var.bedrock_source_profile_arn
  }

  tags = merge(var.tags, {
    Name    = "pr-review-sonnet"
    Purpose = "ci-pr-review"
  })
}

resource "aws_iam_role_policy" "github_actions_bedrock" {
  count = var.create_github_actions_role ? 1 : 0
  name  = "github-actions-bedrock"
  role  = aws_iam_role.github_actions[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvokeModel"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:Converse",
          "bedrock:ConverseStream"
        ]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/*",
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:application-inference-profile/*"
        ]
      },
      {
        Sid    = "BedrockModelDiscovery"
        Effect = "Allow"
        Action = [
          "bedrock:GetFoundationModel",
          "bedrock:ListFoundationModels",
          "bedrock:GetInferenceProfile",
          "bedrock:ListInferenceProfiles"
        ]
        Resource = "*"
      },
      {
        Sid    = "BedrockAgentCore"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:*",
          "bedrock-agentcore-control:*"
        ]
        Resource = "*"
      },
      {
        Sid      = "PassRoleToAgentCore"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*agentcore*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "bedrock-agentcore.amazonaws.com"
          }
        }
      }
    ]
  })
}
