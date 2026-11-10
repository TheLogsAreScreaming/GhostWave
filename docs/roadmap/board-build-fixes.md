# Fix selected board build failures

Status: planning draft. Implementation and verification are pending.

## Scope

Review all 11 jobs from #191. Reproduce each actual failure, apply board-specific fixes, and confirm expected images exist. Do not invent fixes before failures are observed.

## Dependencies

#191

## Acceptance criteria

- [ ] All selected jobs pass on the exact source commit; failures and fixes are documented. A successful compile does not establish hardware compatibility.
- [ ] Review changes and record validation on the exact final commit.

This document does not implement flashing support, publish a release, or establish hardware qualification.
