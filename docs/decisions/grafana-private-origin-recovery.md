# Grafana private-origin recovery — 2026-09-11

AWS-Demo-Platform PR #98 removed the public Grafana NLB to enforce the private
ingress policy. This repository still pointed CloudFront `E2T67VYMCTJW6A` at the
deleted NLB, leaving `grafana-kr.atomai.click` and `grafana.atomai.click` with HTTP
502 while the Grafana Pod remained healthy.

The existing distribution and DNS records stay in this shared Terraform state.
The origin now uses `grafana_vpc_origin_id`, supplied through the environment's
tfvars from AWS-Demo-Platform's `infra/cloudfront` output. That existing VPC Origin
terminates HTTPS on the internal ALB. `grafana-kr.atomai.click` supplies the
wildcard-compatible SNI; the ALB routes both viewer aliases to the Grafana IP
target group through TargetGroupBinding.

Apply AWS-Demo-Platform's target group/listener rule and Kubernetes binding first.
Require at least one healthy target on port 3000 before applying this
distribution's in-place origin change. Preserve the distribution ID, aliases,
existing ACM certificate, disabled caching and AllViewer request policy. This
change must not recreate the public NLB or mutate unrelated shared infrastructure.

During incident recovery, a reviewed saved plan targeting
`aws_cloudfront_distribution.grafana_korea[0]` limits the live change to the
affected distribution. Record any unrelated pending shared-state changes
separately. Verify both aliases' `/login` and `/api/health`, unauthenticated
`/api/user` rejection, CloudFront deployment, target health and ALB security-group
scope. AI review of either repository alone is not a substitute for these
cross-repository and live checks.
