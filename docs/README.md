# Documentation index

This index serves contributors and reviewers of the independent c-plugin migration.
For end-user availability, start with the [root README](../README.md).

- [Saved CLI reference](./cli.md): implemented-in-snapshot commands, examples, and current limitations.
- [Design contract](./design/contract.md) and [Japanese translation](./design/contract.ja.md): current constraints and explicitly planned capabilities.
- [Migration ledger](./migration.md): immutable provenance, stage dependencies, source links, and validation boundaries.
- E2E scenario documents: [init](../go/e2e/c-plugin/init_test.md), [add](../go/e2e/c-plugin/add_test.md), [remove](../go/e2e/c-plugin/remove_test.md), [sync](../go/e2e/c-plugin/sync_test.md), [recursive sync](../go/e2e/c-plugin/sync_recursive_test.md), [target add](../go/e2e/c-plugin/target_add_test.md), and [target remove](../go/e2e/c-plugin/target_remove_test.md).

The initial documentation layer includes the seven scenario documents, not their Go implementations.
Their expected results describe source assertions, not successful runs performed by this documentation-only change.
