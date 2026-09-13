<!-- Parent: ../AGENTS.md -->
<!-- Updated: 2026-09-13 -->

# PR Review

## Purpose
Legacy review scripts and inactive common specialist executors. MRA requires its
configured adapter before preparation; the operational workflow remains legacy.
The live workflow still calls the legacy panel and chair; the protocol is not activated.

## Key Files
| File | Responsibility |
| --- | --- |
| [collect-diff.sh](collect-diff.sh) | Existing files API classifier; preserves state/plan deny and deletion-content withholding. |
| [lib.sh](lib.sh) | Existing slot and output-scrubbing helpers. |
| [run-panel.sh](run-panel.sh) | Operational legacy panel entrypoint. |
| [synthesize.sh](synthesize.sh) | Operational legacy chair entrypoint. |
| [test-collect-diff.sh](test-collect-diff.sh) | Existing executable collector regression checks. |
| [role_review.py](role_review.py) | Offline protocol: prepare, issue, record and aggregate; not used by the live workflow. |
| [test_role_review.py](test_role_review.py) | Offline protocol regression tests. |
| [README.md](README.md) | Command, file-schema and stage contracts. |
| [prepare_roles.py](prepare_roles.py) | Trusted preparation; MRA requires its configured adapter. |
| [role-project.json](role-project.json) | BASE-bound MRA guard for adapter selection and role-based chair limits. |
| [test_mra_bootstrap_roles.py](test_mra_bootstrap_roles.py) | Bootstrap fail-closed, chair and Claude command checks. |
| [run-specialists.sh](run-specialists.sh), [run_role.py](run_role.py) | Common provider execution; not selected by MRA CI. |
| [synthesize_roles.py](synthesize_roles.py) | Common conditional chair. |
| [role-controls.sh](role-controls.sh) | `strip_ansi`; `run_role.scrub()` adds `lib.sh` secret masking. |
| [test_prepare_roles.py](test_prepare_roles.py), [test_project_policy_roles.py](test_project_policy_roles.py) | Trusted input and policy tests. |
| [test_run_role.py](test_run_role.py), [test_synthesize_roles.py](test_synthesize_roles.py), [test_integrity_roles.py](test_integrity_roles.py) | Executor, chair and cross-stage tests. |

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
Current check: `bash scripts/pr-review/test-collect-diff.sh`.
Protocol checks:

```bash
python3 -m unittest discover -s scripts/pr-review -p 'test_*role*.py' -v
```

<!-- MANUAL: -->
