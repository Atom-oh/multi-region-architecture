# ADR-005: Introduce the specialist review protocol before activation

## Status

Accepted (2026-09-13). PR #52 installs the protocol/tests; policy PR #53's rationale
is preserved below. Legacy review remains active; provider/adapter rollout follows.

## Context

The specialist design assigns distinct responsibilities while retaining independent
Codex/Claude coverage and explicit failures. Combining protocol, executors, project
adaptation and activation makes the native review input too large. The rollout
therefore separates the implementation without increasing review budgets or
removing meaningful tests.

Multi-Region Architecture (MRA) already has operational contracts for collector classification, sensitive
deletions and bounded adjudication. Adding a protocol must not silently replace
those controls or imply that a new workflow is active.

## Decision

This PR records the contract. The following implementation PR will add
`role_review.py`, `test_role_review.py` and their offline test workflow. The library prepares role inputs,
validates responses and aggregates coverage. It binds supplied provenance and
invocation-nonce metadata; it performs no Git fetch, provider call or publication.
Its [README](../../scripts/pr-review/README.md) defines the CLI and outcome modes.

The library blocks incomplete input and diffs exceeding 95,000 bytes or 3,000
lines, without prefix credit. Context and complete-request limits also apply.
There is no automatic chunking. Library limits do not change the existing
operational workflow in this PR.

Phase two adds provider executors, the project-policy loader, MRA input adapter,
chair integration and activation tests. The supplied collector view and safe
provenance must reach that integration without a raw Git reconstruction that
restores excluded state contents. Canonical CLAUDE.md plus an ADR summary must
reach reviewers without file tools.

**Approved generic exclusions-only result.** Repository maintainers approve the
scope policy through review of the committed BASE configuration. The trusted
preparer, never a model response, may select `configured_exclusions_only` when
all changed paths are covered by that policy. The prepared diff and reviewable
path list must be empty; nonempty `scope_paths` and `excluded_paths` must match,
and `input_policy_sha256` must identify the verified BASE policy. Missing,
unknown or accidentally empty input and provider failures do not qualify.

For this approved case the protocol may make all roles inactive, invoke no models,
and produce a deterministic `NOT_APPLICABLE` explanation followed by
`VERDICT: PASS`. This PASS means the approved scope check passed, not that models
reviewed the change. The report must disclose the excluded paths and policy hash.
If any reviewable input remains, the independent primary-role requirement applies.

**Policy artifacts (planned).** For generic consumers, the reviewed source is
`scripts/pr-review/role-input-scope.json` in the pinned BASE commit. The trusted
caller passes a byte-identical local copy using `--policy FILE`. Preparation will
retain the verified bytes as `WORK/exclusions-policy.json`: a generated private
validation copy, not a second committed policy. `input_policy_sha256` hashes the
exact BASE policy bytes; both local copies must match it. Aggregation will recheck
the retained WORK copy against that digest. The caller still owns verification of
the BASE source and complete Git scope.

**Required generic integration.** Before requesting this exception, the trusted
BASE preparer must verify its checkout, read the policy blob from `base_sha`, and
derive the complete changed-path set from immutable Git objects. It must supply
the generic and exception fields in the README's
[canonical provenance table](../../scripts/pr-review/README.md#provenance-planned).
That table distinguishes the complete source diff from the approved protocol input
and specifies which component verifies each hash.
Candidate-supplied policy/scope assertions and model output are not authoritative.
Missing or incomplete evidence must fail closed, never become NOT_APPLICABLE.

**Accepted boundary.** Hashes bind the supplied evidence; they do not authenticate
an arbitrary caller. Git/source verification belongs to the trusted BASE preparer,
not the offline library. A universal file-type denylist is deliberately absent:
reviewed policies can legitimately exclude generated code, including generated
IaC. Consumer-specific eligibility belongs to that reviewed policy and collector.
A defective trusted collector or approved policy remains a reviewable integration
risk, not a guarantee supplied by the hash check. MRA authorizes none of this
generic exclusion policy; its separate ADR-004 deny rules remain mandatory.

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
Protocol PASS means supplied role evidence validated; it is not a live provider
result or permission to skip activation review.

After the implementation files exist, run
`python3 -B -m unittest discover -s scripts/pr-review -p test_role_review.py -v`.
The phase-two integration needs its own current-HEAD review and tests for the
collector bundle, nondisclosure, provenance, provider failures and chair controls.

The owner selects Kiro's `gpt-5.6-sol` alias to replace `gpt-5.6-terra` in the
`kiro-gpt` slot (`run-panel.sh`), retaining its review responsibilities. The
historical `bedrock-mantle` Sol comment in that script describes Codex's earlier
provider, not Kiro's catalog. Codex stays on Runtime/Astra; no Mantle region policy
is reversed. Kiro model selection remains subject to runtime preflight. This
records a future Kiro selection, not a claim that it is already active.
The [README mapping](../../scripts/pr-review/README.md#slot-mapping-planned)
distinguishes protocol tags from legacy slot labels.
