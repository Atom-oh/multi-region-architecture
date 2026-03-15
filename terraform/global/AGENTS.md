<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# Global Terraform Resources

## Purpose
Cross-region and region-agnostic resources that span the entire multi-region deployment. These must be deployed before or alongside regional infrastructure.

## Key Subdirectories
- `terraform-state/` — S3 bucket and DynamoDB table for remote state storage and locking
- `aurora-global-cluster/` — Aurora Global Database spanning us-east-1 (writer) and us-west-2 (reader)
- `documentdb-global-cluster/` — DocumentDB Global Cluster for cross-region document storage
- `route53-zone/` — Hosted zone for DNS management and health-based routing

## For AI Agents
### Working In This Directory
- **Bootstrap first**: `terraform-state/` must be deployed manually before other modules (chicken-and-egg).
- **Global state**: These resources use a separate state file (`global/terraform.tfstate`).
- **Cross-region references**: Aurora and DocumentDB global clusters reference regional VPCs/subnets.
- **DNS is global**: Route53 hosted zone is not region-scoped; records point to regional endpoints.
- **Careful with destroy**: Global resources affect all regions; destroying them impacts the entire platform.

### Deployment Sequence
```
1. terraform-state/     (manual bootstrap, no remote state)
2. route53-zone/        (DNS foundation)
3. [Deploy regional infrastructure in environments/]
4. aurora-global-cluster/    (after regional VPCs exist)
5. documentdb-global-cluster/ (after regional VPCs exist)
```

<!-- MANUAL: -->
