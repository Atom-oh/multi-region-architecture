# ADR-005: Introduce the specialist review protocol before activation

## Status

Accepted (2026-09-13). The protocol is installed. This stage adds inactive common
executors and unit tests. The MRA guard profile is installed here; its adapter implementation follows, then
workflow activation and E2E tests. The legacy operational path remains selected. The early MRA profile blocks
preparation before raw Git fallback until its adapter is installed, and enforces
600-second/8/12-turn chair limits even during this inactive stage.

## Context

The specialist design assigns distinct responsibilities while retaining independent
Codex/Claude coverage and explicit failures. Combining protocol, executors, project
adaptation and activation makes the native review input too large. The rollout
therefore separates the implementation without increasing review budgets or
removing meaningful tests.

MRA already has operational contracts for collector classification, sensitive
deletions and bounded adjudication. Adding a protocol must not silently replace
those controls or imply that a new workflow is active.

## Decision

Phase one contains `role_review.py`, `test_role_review.py`, protocol documentation
and their dedicated offline test workflow. The library prepares role inputs,
validates responses and aggregates coverage. It binds supplied provenance and
invocation-nonce metadata; it performs no Git fetch, provider call or publication.
Its [README](../../scripts/pr-review/README.md) defines the CLI and outcome modes.

The library blocks incomplete input and diffs exceeding 95,000 bytes or 3,000
lines, without prefix credit. Context and complete-request limits also apply.
There is no automatic chunking. Library limits do not change the existing
operational workflow in this PR.

Implementation is split into common executors/tests, the MRA adapter/policy/tests,
and final workflow activation/E2E. No stage raises the review input limit. The supplied collector view and safe
provenance must reach that integration without a raw Git reconstruction that
restores excluded state contents. Canonical CLAUDE.md plus an ADR summary must
reach reviewers without file tools.

**Approved generic exclusions-only result.** Repository maintainers approve the
scope policy through review of the committed BASE configuration. The trusted
preparer, never a model response, may select `configured_exclusions_only` when
all changed paths are covered by that policy. The prepared diff and reviewable
path list must be empty; nonempty `scope_paths` and `excluded_paths` must match,
and `input_policy_sha256` must identify the verified BASE policy. Explicit
`--allow-exclusions-only --policy FILE` anchors its actual bytes; the caller MUST
verify BASE policy provenance and complete Git scope. Missing,
unknown or accidentally empty input and provider failures do not qualify.

For this approved case the protocol may make all roles inactive, invoke no models,
and produce a deterministic `NOT_APPLICABLE` explanation followed by
`VERDICT: PASS`. This PASS means the approved scope check passed, not that models
reviewed the change. The report must disclose the excluded paths and policy hash.
If any reviewable input remains, the independent primary-role requirement applies.

This generic library capability does not broaden MRA's ADR-004 exception. MRA
continues to use its custom files API collector, state-body withholding and the
narrow deletion-only workflow shortcut. These MRA stages do not introduce a
`role-input-scope.json` policy or select `configured_exclusions_only` for MRA.

Existing decisions remain in force:

- [ADR-002](ADR-002-pr-review-kiro-fs-read-risk.md): preserve trusted execution and
  credential boundaries. A configured model or tool flag alone is not runtime proof.
- [ADR-003](ADR-003-eks-mgmt-ownership-handoff.md): management-cluster state custody
  remains with AWS-Demo-Platform; this PR changes no infrastructure ownership.
- [ADR-004](ADR-004-pr-review-empty-diff-exception.md): retain files API classification,
  both rename paths, state/plan deny rules, deletion-content withholding and the
  narrowly eligible deletion-only exception. Preserve the 600-second chair limits,
  8/12 turn caps and mandatory tool deny baseline when integrating phase two.

## Consequences and verification

The current `pr-review.yml`, collector and chair execution path are unchanged.
Protocol PASS means validated role evidence or an approved exclusions-only scope.
It does not attest live provider execution or waive activation review.

Run
`python3 -B -m unittest discover -s scripts/pr-review -p 'test_*role*.py' -v`.
The phase-two integration needs its own current-HEAD review and tests for the
collector bundle, nondisclosure, provenance, provider failures and chair controls.

The target Sol configuration intentionally replaces the legacy Terra review slot
for consistent fleet configuration. This is an explicit target selection, not a
claim that Sol is already LIVE or a change to the application inference models.
