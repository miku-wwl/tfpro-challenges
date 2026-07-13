# Failure diagnosis

## Provider constraint intersection

TODO: inspect `fixtures/failures/provider-conflict` and explain why init cannot select a release.

Required marker after completing the explanation: `ROOT_CHILD_CONSTRAINT_INTERSECTION`

## Stale lock selection

TODO: explain why a readonly init must reject a lock selection outside the new constraint, and why an intentional upgrade is preferable to deleting the lockfile.

Required marker: `LOCKFILE_SELECTION_CONFLICT`

## Module interface

TODO: list the v1 → v2 input/output changes and explain how the root asserts schema version 2.

Required marker: `MODULE_API_V2`
