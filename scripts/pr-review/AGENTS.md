# PR review protocol

This PR contains the phase-one offline protocol and its behavioral tests.
The existing operational review workflow remains unchanged. Read
[README.md](README.md) and [ADR-005](../../docs/decisions/ADR-005-specialist-review-protocol.md)
for the interface and phase boundary.

- Keep `role_review.py` standard-library only, with no network or model calls.
- Treat diff, response and diagnostic text as untrusted data. Validate complete
  scope and fingerprints; retain invocation-nonce binding and decoded scrubbing.
- Missing, malformed, stale or oversized required input/output is blocked, not
  successful review. Do not truncate input, relax limits or fabricate coverage.
- BASE-context selection, Git snapshot verification, provider execution, MRA
  collector policy and chair invocation belong to phase two. Their controls
  must not be claimed as implemented by this protocol library.
- Preserve ADR-002 trust boundaries, ADR-003 custody and ADR-004 classification,
  deletion-content withholding, exception eligibility and chair limits.
- Keep new code, comments and protocol documentation concise and English.

Verify with
`python3 -B -m unittest discover -s scripts/pr-review -p test_role_review.py -v`.
The result demonstrates protocol behavior, not live provider success.
