# Documentation index

This index serves contributors and reviewers of c-plugin.
For end-user availability, start with the [root README](../README.md).

- [CLI reference](./cli.md): implemented commands, examples, and current limitations.
- [Design contract](./design/contract.md) and [Japanese translation](./design/contract.ja.md): current constraints and explicitly planned capabilities.
- E2E scenario documents: [init](../go/e2e/c-plugin/init_test.md), [add](../go/e2e/c-plugin/add_test.md), [remove](../go/e2e/c-plugin/remove_test.md), [sync](../go/e2e/c-plugin/sync_test.md), [recursive sync](../go/e2e/c-plugin/sync_recursive_test.md), [target add](../go/e2e/c-plugin/target_add_test.md), and [target remove](../go/e2e/c-plugin/target_remove_test.md).

The seven scenario documents describe the eight registered Go/Testcontainers cases.
Their expected results describe source assertions, not successful test-run evidence.
