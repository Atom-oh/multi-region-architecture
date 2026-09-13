# Specialist PR review

CI assigns distinct responsibilities instead of asking every model to repeat
every review lens. The trusted workflow enables this protocol with
`ROLE_REVIEW=1`; legacy matrix entrypoints remain for regression fixtures.

| Slot | Configured model | Responsibility |
| --- | --- | --- |
| `codex` | `global.openai.gpt-6-astra` | Implementation, concurrency, errors and tests |
| `kiro-fable` | `claude-opus-5` | AWS architecture, IAM, networking and service constraints |
| `kiro-sol` | `gpt-5.6-sol` | Deployment order, component contracts, lifecycle and recovery |
| `claude-self` | `global.anthropic.claude-fable-5-1` | Authentication, data boundaries, requirements, API and ADR consistency |

The protocol `kiro-fable` tag identifies the Opus slot. Kiro catalog aliases differ
from Bedrock inference-profile IDs. These are configured model identities, not
attestation of the provider's internal routing or weights.

## Routing and evidence

Trusted code determines which roles apply. Codex and Claude review the full change
boundary, retaining independent OpenAI/Anthropic checks for sensitive changes.
Kiro roles run for applicable AWS and operational changes, including relevant
documentation. Unfamiliar paths route conservatively. Only deterministic routing
may record NOT_APPLICABLE; provider failures never do.

`prepare_roles.py` verifies the pinned base checkout, resolves the immutable merge
base and fetches Git objects as data. MRA's trusted adapter consumes the approved
collector view before any generic raw-diff path. Reviewable text stays complete;
excluded state bodies remain withheld and their paths stay in provenance. BASE
CLAUDE.md plus the ADR summary supplies context; candidate context is checked for
availability/size without becoming instructions. The context ceiling is 24,000 bytes.
See the [MRA input contract](../scripts/pr-review/README.md) for exact bundle,
issued-request, receipt and artifact paths.

Every result confirms its role, HEAD and reviewed paths. Host metadata binds it
to the prepared request and an issued nonce/receipt, and records the process status.
A self-declared nonce cannot substitute for issuance. Nonzero exits, malformed
or empty reports, missing paths, invalid fingerprints, model selection errors,
quota exhaustion and failed required roles block coverage. A JSON shape is
evidence of protocol completion, not proof that the model found every defect.

The protocol accepts the complete approved view within 3,000 lines and 95,000
UTF-8 bytes. Oversized input blocks without prefix credit. MRA has no automatic
chunking path; keep each common-executor, adapter and activation delta within the
existing limits.

## Execution and synthesis

Each applicable model receives one specialist request. Both Kiro roles use fresh
HOME/cwd directories and a profile declaring no tools, MCP servers, resources or
hooks. Each active Kiro job first receives a random canary check without PR data;
only an exact successful no-tools response permits the actual review. Its child
environment excludes AWS and GitHub credentials. Errors remain visible; no
automatic quota or billing changes are made.

Codex retains its read-only sandbox and configured Bedrock provider. Its JSONL
events validate execution; the CLI-designated private final reply supplies review
text, excluding tool/progress output. Claude's specialist has no tools. The chair
has bounded local read tools and no GitHub token. Review output is scrubbed before
becoming a public artifact.

Complete, valid results with no Critical/Major candidate or uncertainty receive
a deterministic summary. Other valid results require chair adjudication. A
coverage failure receives a deterministic failure; a chair cannot waive it.
Minor/Info findings remain in the report.

With all four roles active, the ordinary path uses four review calls and two
Kiro startup checks. Adjudication adds one chair call; retries and fallback add
calls only when needed. This reduces duplicate requests, but is not a measured
wall-clock speedup. Per-role timing artifacts support before/after measurement.

## Maintenance and release

Run `python3 -m unittest discover -s scripts/pr-review -p 'test_*role*.py' -v`
and the repository's existing review tests. Offline fake CLIs validate routing,
scope, subprocess status and safety boundaries without spending model credits.
They do not establish successful live model execution.

Native `pull_request_target` uses base scripts, so a workflow-changing PR must
also have offline checks for the candidate implementation. Review the latest HEAD,
resolve real Critical/Major findings, satisfy required CI and branch rules, and
verify the integration path before merge. Missing review or quota failure is not
a clean result. Model limits and required gates remain in force.
