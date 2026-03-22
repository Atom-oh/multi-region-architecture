data "aws_caller_identity" "current" {}

# IRSA role for service pods that need DSQL access
resource "aws_iam_role" "dsql_access" {
  name = "${var.environment}-dsql-access-${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "${var.oidc_provider_url}:sub" = "system:serviceaccount:*:*"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "dsql_connect" {
  name = "${var.environment}-dsql-connect-policy"
  role = aws_iam_role.dsql_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dsql:DbConnectAdmin",
          "dsql:DbConnect"
        ]
        Resource = var.dsql_cluster_arn
      }
    ]
  })
}
