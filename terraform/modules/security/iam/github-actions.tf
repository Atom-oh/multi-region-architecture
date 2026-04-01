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
        Resource = "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_repository_prefix}/*"
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
# Bedrock — Application Inference Profile for PR review token tracking
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_bedrock_inference_profile" "pr_review" {
  count       = var.create_github_actions_role ? 1 : 0
  name        = "pr-review-sonnet"
  description = "PR review inference profile for GitHub Actions CI — token usage tracking"

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
  name  = "github-actions-bedrock-pr-review"
  role  = aws_iam_role.github_actions[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvokeModel"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          aws_bedrock_inference_profile.pr_review[0].arn,
          "arn:aws:bedrock:${var.region}::foundation-model/${var.bedrock_pr_review_model_id}",
          "arn:aws:bedrock:*::foundation-model/${var.bedrock_pr_review_model_id}"
        ]
      },
      {
        Sid    = "BedrockGetInferenceProfile"
        Effect = "Allow"
        Action = [
          "bedrock:GetInferenceProfile",
          "bedrock:ListInferenceProfiles"
        ]
        Resource = "*"
      }
    ]
  })
}
