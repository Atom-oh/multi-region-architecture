# ─────────────────────────────────────────────────────────────────────────────
# ECR repositories — image build targets for scripts/build-and-push.sh,
# scripts/seed-data/build-and-push-seed.sh, and .github/workflows/build-services.yml
#
# These were originally created ad-hoc (aws ecr create-repository / CI push).
# Codifying them makes the repo fully self-contained: a fresh account only
# needs `terraform apply` here, then AWS_ACCOUNT_ID=... AWS_REGION=ap-northeast-2
# scripts/build-and-push.sh to reproduce every image from committed source.
#
# Adopting in THIS account (repos already exist — plain apply would 409):
#   for r in api-gateway event-bus cart search inventory product-catalog analytics \
#            user-profile wishlist review shipping recommendation notification \
#            order payment user-account warehouse returns pricing seller \
#            synthetic-monitor seed-data; do
#     terraform import "aws_ecr_repository.services[\"$r\"]" "shopping-mall/$r"
#   done
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # 20 microservices + synthetic-monitor + seed-data (see scripts/build-and-push.sh)
  ecr_services = [
    # Go (5)
    "api-gateway", "event-bus", "cart", "search", "inventory",
    # Python (8)
    "product-catalog", "analytics", "user-profile", "wishlist",
    "review", "shipping", "recommendation", "notification",
    # Java (7)
    "order", "payment", "user-account", "warehouse", "returns", "pricing", "seller",
    # Standalone
    "synthetic-monitor", "seed-data",
  ]
}

resource "aws_ecr_repository" "services" {
  for_each = toset(local.ecr_services)

  name                 = "shopping-mall/${each.key}"
  image_tag_mutability = "MUTABLE" # CI re-tags :latest on every push

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.tags, {
    Name = "shopping-mall/${each.key}"
  })
}

# Keep only recent untagged images — CI pushes :sha + :latest on every merge,
# so untagged layers accumulate fast.
resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images older than 14 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 14
      }
      action = { type = "expire" }
    }]
  })
}

output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL"
  value       = { for k, r in aws_ecr_repository.services : k => r.repository_url }
}
