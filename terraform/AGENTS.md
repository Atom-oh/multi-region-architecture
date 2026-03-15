<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# Terraform Infrastructure

## Purpose
Infrastructure as Code (IaC) for AWS multi-region deployment (us-east-1 primary, us-west-2 secondary). Manages all cloud resources for the shopping mall platform.

## Key Subdirectories
- `modules/` — Reusable Terraform modules (networking, compute, data, edge, observability, security)
- `environments/` — Per-region root configurations (production/us-east-1, production/us-west-2)
- `global/` — Cross-region resources (Aurora global cluster, Route53 zone, Terraform state backend)
- `scripts/` — Helper scripts for plan, apply, destroy, and validation

## For AI Agents
### Working In This Directory
- **State is remote**: S3 bucket + DynamoDB for locking. Never commit `.tfstate` files.
- **Plan before apply**: Always run `terraform plan` and review output before `terraform apply`.
- **Module convention**: Each module has `main.tf`, `variables.tf`, `outputs.tf`.
- **Environment isolation**: Each region has its own state file; changes are region-scoped.
- **Dependency order**: Global resources (terraform-state, route53-zone) must exist before regional deploys.
- **Required versions**: Terraform >= 1.5, AWS provider >= 5.0.

### Common Operations
```bash
# Initialize a module
terraform -chdir=environments/production/us-east-1 init

# Plan changes
terraform -chdir=environments/production/us-east-1 plan -out=tfplan

# Apply changes
terraform -chdir=environments/production/us-east-1 apply tfplan

# Validate all configurations
./scripts/validate-all.sh
```

<!-- MANUAL: -->
