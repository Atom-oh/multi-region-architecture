<!-- Parent: ../AGENTS.md -->
<!-- Updated: 2026-09-13 -->

# PR Review

## Purpose
Owns the activated specialist workflow, collector adapter and protocol.
The operational workflow selects `ROLE_REVIEW=1`; legacy matrix branches remain for compatibility.

## Key Files
| File | Responsibility |
| --- | --- |
| [collect-diff.sh](collect-diff.sh) | Existing files API classifier; preserves state/plan deny and deletion-content withholding. |
| [lib.sh](lib.sh) | Existing slot and output-scrubbing helpers. |
| [run-panel.sh](run-panel.sh) | Operational bridge to the specialist coordinator. |
| [synthesize.sh](synthesize.sh) | Operational bridge to conditional specialist synthesis. |
| [test-collect-diff.sh](test-collect-diff.sh) | Existing executable collector regression checks. |
| [role_review.py](role_review.py) | Offline protocol used by the installed provider libraries. |
| [test_role_review.py](test_role_review.py) | Offline protocol regression tests. |
| [README.md](README.md) | Command, file-schema and stage contracts. |
| [prepare_roles.py](prepare_roles.py) | Trusted preparation and project-policy selection. |
| [prepare_project_roles.py](prepare_project_roles.py) | MRA collector bundle verification; never reconstructs withheld state bodies. |
| [role-project.json](role-project.json) | BASE-bound MRA context sources and mandatory chair settings. |
| [mra-review-context.md](mra-review-context.md) | Bounded ADR context accompanying canonical BASE CLAUDE.md. |
| [run-specialists.sh](run-specialists.sh) | Installed provider coordinator; retains current upstream failure flags. |
| [run_role.py](run_role.py) | Provider execution with issued-request receipts and failure recording. |
| [synthesize_roles.py](synthesize_roles.py) | Deterministic output or bounded adjudication; no coverage override. |
| [role-controls.sh](role-controls.sh) | ANSI/control stripping, combined with `lib.sh` secret masking by `run_role.scrub()`. |
| [test_mra_bootstrap_roles.py](test_mra_bootstrap_roles.py) | Guard, per-slot evidence cap and tool-denial regressions. |
| `test_{prepare,project_policy,run,synthesize,integrity}_roles.py` | Preparation, policy, execution, chair and cross-stage regressions. |
| [test_project_roles.py](test_project_roles.py) | MRA collector and policy binding tests. |
| [test_e2e_roles.py](test_e2e_roles.py) | Generic temporary-fixture executor scenarios. |
| [test_project_integration_roles.py](test_project_integration_roles.py), [test_project_workflow_roles.py](test_project_workflow_roles.py) | MRA entrypoints, workflow and credential boundaries. |

## Subdirectories
| Directory | Purpose |
| --- | --- |
| (none committed) | Generated `roles/`, `requests/` and `slot/` directories belong to caller WORK, not the source tree. |

## For AI Agents
- Use [README.md](README.md) and [ADR-005](../../docs/decisions/ADR-005-specialist-review-protocol.md) for current stage and API contracts.
- Distinguish live wrappers, installed libraries and offline protocol behavior. Library presence alone does not activate CI.
- Keep the protocol standard-library only. Treat diff, output and metadata as data; validate scope, issued receipts and fingerprints.
- Bounded-input failures and invalid/missing required responses block. Request limits do not imply an output-size validator.
- `configured_exclusions_only` is an explicitly approved generic protocol outcome, never a model-assigned exemption. MRA keeps ADR-004's custom collector and deletion-only shortcut; no generic MRA exclusion policy is introduced.
- Preserve ADR-002 trust boundaries and ADR-003 custody. Keep state bodies out of review input and preserve current upstream failure flags.
- New code, comments and review documentation are English. Offline checks are not proof of live model execution.

## Testing Requirements
Run from the repository root:

```bash
python3 -m unittest discover -s scripts/pr-review -p 'test_*role*.py' -v
bash scripts/pr-review/test-collect-diff.sh
```

<!-- MANUAL: -->
