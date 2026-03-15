<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# Base Resources

## Purpose
Shared Kubernetes resources applied to all regions: namespace definitions, network policies for security isolation, and resource quotas per service category.

## Key Files
| File | Description |
|------|-------------|
| `kustomization.yaml` | Aggregates all base resources |
| `namespaces.yaml` | Namespace definitions for all service categories |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `network-policies/` | NetworkPolicy resources for pod-to-pod traffic control |
| `resource-quotas/` | ResourceQuota limits per namespace |

### Network Policies
| File | Description |
|------|-------------|
| `default-deny.yaml` | Deny all ingress/egress by default |
| `allow-dns.yaml` | Allow DNS resolution (kube-dns) |
| `allow-alb-ingress.yaml` | Allow traffic from AWS ALB |
| `allow-inter-namespace.yaml` | Allow cross-namespace service calls |

### Resource Quotas
| File | Description |
|------|-------------|
| `core-services.yaml` | Quotas for core namespace (product, cart, order, payment) |
| `user-services.yaml` | Quotas for user namespace |
| `fulfillment.yaml` | Quotas for fulfillment namespace |
| `business-services.yaml` | Quotas for business namespace |
| `platform.yaml` | Quotas for platform namespace |

## For AI Agents
### Working In This Directory
- Network policies follow deny-by-default pattern; add explicit allow rules
- Resource quotas set CPU/memory limits per namespace
- All resources get label `app.kubernetes.io/managed-by: kustomize`
- Changes here affect ALL regions via overlay inheritance

<!-- MANUAL: -->
