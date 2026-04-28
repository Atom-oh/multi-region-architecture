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
    Statement = [
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
    ]
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
        Sid    = "PassRoleToECS"
        Effect = "Allow"
        Action = "iam:PassRole"
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
      }
    ]
  })
}
