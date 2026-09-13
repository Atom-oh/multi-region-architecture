# Review protocol — phase one

This PR adds the offline, standard-library `role_review.py` protocol, its tests
and a dedicated test workflow. Provider executors, the MRA collector adapter,
project policy and workflow activation belong to phase two.

The current `pr-review.yml`, collector classification, state-deletion protections,
chair controls and infrastructure custody are unchanged. See
[ADR-005](../../docs/decisions/ADR-005-specialist-review-protocol.md) for the split.

## Interface

Run `python3 scripts/pr-review/role_review.py <command> --help` for exact arguments.

| Command | Inputs and result |
| --- | --- |
| `prepare` | Requires `--diff`, `--context`, `--head`, `--base`, `--work`; accepts `--paths`, `--provenance`, `--context-cap`. Writes the role plan and required-role input files. |
| `record` | Requires `--work`, `--tag`, `--output`, `--stderr`, `--exit-code`, `--nonce`. Validates a response and writes its slot result. |
| `aggregate` | Requires `--work`. Validates required results and writes scope, failure and synthesis-mode artifacts. |

The caller supplies approved diff bytes, trusted BASE context and full 40-hex
revision identifiers. The protocol does not fetch Git objects, verify checkout
identity, classify MRA exclusions, invoke providers or publish reviews.

Plans bind input/provenance fingerprints. Recording binds a caller-supplied
32-hex invocation nonce, validates the JSON role/HEAD/path assertions and scrubs
decoded response strings. Provider diagnostics, invalid output and missing or
stale required results cannot count as completed coverage. Configured model
identities and scope assertions are not proof of actual model execution.

## Outcomes and limits

Codex and Claude are required across model families; deterministic routing may
deactivate Kiro only for clearly irrelevant changes. Unknown scope stays active.
The role/model mapping is maintained in `role_review.py`.

The protocol blocks diff input over 95,000 UTF-8 bytes or 3,000 lines. Context
defaults to a 24,000-byte ceiling, optionally lower; complete requests also have
a 128 KiB limit. Input is not truncated and no automatic chunking is implemented.
These are library limits, not a change to the current workflow.

Exit 2 means blocked. Aggregate exit 0 requires reading `chair-mode.txt`:
`deterministic` produces a PASS summary; `review` requires later adjudication.
Blocked coverage produces FAIL and cannot be waived by a chair. This library
does not execute the adjudicator.

## Verification

```bash
python3 -B -m unittest discover -s scripts/pr-review -p test_role_review.py -v
```

The phase-one test workflow runs this protocol suite only. Executor, collector
adapter and activation tests are phase-two material. Offline checks do not
establish successful live inference or deployment.
