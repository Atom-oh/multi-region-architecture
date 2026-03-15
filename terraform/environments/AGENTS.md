<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# Terraform Environments

## Purpose
Root configurations for each deployment region. These compose modules into complete infrastructure stacks with region-specific settings.

## Key Subdirectories
- `production/us-east-1/` — Primary region (active traffic)
- `production/us-west-2/` — Secondary region (failover, read replicas)

## Key Files (per region)
- `main.tf` — Module composition and resource orchestration
- `variables.tf` — Input variable definitions
- `terraform.tfvars` — Region-specific variable values
- `backend.tf` — Remote state configuration (S3 + DynamoDB)
- `outputs.tf` — Exported values for cross-stack references

## For AI Agents
### Working In This Directory
- **Each region is independent**: Changes to us-east-1 do not affect us-west-2 state.
- **Initialize first**: Run `terraform init` before any plan/apply in a new region.
- **Use tfvars**: Never hardcode region-specific values in `main.tf`; put them in `terraform.tfvars`.
- **State isolation**: Each region has its own state key in the S3 backend.
- **VPC CIDR planning**: us-east-1 uses `10.1.0.0/16`, us-west-2 uses `10.2.0.0/16` (non-overlapping for peering).

### Deployment Order
1. Ensure `global/terraform-state` exists (bootstrap)
2. Deploy us-east-1 (primary)
3. Deploy us-west-2 (secondary)
4. Global resources (aurora-global-cluster, route53-zone) reference both regions

<!-- MANUAL: -->
