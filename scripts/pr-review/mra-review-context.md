# MRA ADR context

- **ADR-002:** Execute BASE, never PR data; no stored checkout credentials.
  Kiro needs an empty catalog, isolated HOME/environment and fixed no-tools canary,
  beyond scrubbing/`--trust-tools=`.
- **ADR-003:** AWS-Demo-Platform owns Korea management state; removing MRA's layer cannot alter it.
  Spoke lookups check VPC/tags, nonempty SG, ACTIVE/UPDATING; overrides check VPC/tags.
- **ADR-004 D1/D3:** Classify files API metadata and both rename paths with
  `collect-diff.sh`; no raw Git reconstruction.
  State/plan additions/modifications/renames block; deletions withhold bodies.
  Retain disguised text/source-boundary renames; audit exclusions.
- **ADR-004 shortcut:** Only nonempty eligible binary image/document and/or
  state/plan deletions skip providers; never lockfiles, additions, archives,
  containers or empty input. Review mixed text. API-omitted oversized text deletions
  use metadata, never recovered bodies.
- **ADR-004 chair:** 600 seconds each, 8/12 primary/fallback turns. Always deny
  Bash, Write, Edit, NotebookEdit, WebFetch, WebSearch, Task despite empty overrides.
  Read/Grep/Glob lack path confinement.

Report missing peer-region changes against their changed counterparts with evidence.
