# Initialize project and global locks

Source: [init_test.go](./init_test.go)

The relative Source link identifies the sibling Go implementation described below.
The two functions below are independently registered cases. They call the shared `runInitWorkflow` helper, which is not a separately registered scenario.

## `initProjectScenario`

### Scope

Create the project lock exclusively and reject a repeated initialization without synchronization side effects.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Exclusively create the selected lock and reject a repeated initialization. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| None | Both invocations select the current project scope without a global flag. |

### Preconditions and fixtures

- Each registered case receives its own `c-plugin-e2e:local` container.
- `HOME=/tmp/c-plugin-v2-init-e2e/home` and `PROJECT=/tmp/c-plugin-v2-init-e2e/totto2727-org/monorepo` are synthetic container paths.
- The helper creates HOME and PROJECT directories with no existing project/global lock, marketplace, cache, ownership state, or managed skill directory.
- `c-plugin` denotes `/sandbox/.local/bin/c-plugin`; argv is passed directly with `WorkingDir=$PROJECT` and the isolated HOME.

### Execution flow

1. Run `c-plugin init` from `$PROJECT`.
2. Check `Created <absolute selected lock path>\n`, the empty lock JSON at `$PROJECT/c-plugin-lock.json`, and the absence of `$HOME/c-plugin-lock.json`. Record the created lock digest.
3. Run `c-plugin init` from `$PROJECT`.
4. Verify nonzero status, the expected error substring, and an unchanged lock digest.
5. Check that neither project nor home `.agents` nor `$HOME/.cache/c-plugin` was created, and the opposite-scope lock remains absent.

### Expected results

| Observation | Expected result |
| --- | --- |
| Initial status/output | Exit 0; exactly `Created <absolute selected lock path>\n` in captured output. |
| Lock JSON | Exactly the JSON value `{"version":"2","targets":[],"repositories":[]}`; object key ordering is not asserted by the JSON helper. |
| Scope isolation | `$PROJECT/c-plugin-lock.json` exists and `$HOME/c-plugin-lock.json` is absent. |
| Repeated status/output | Nonzero exit; captured output contains `totto2727/c-plugin.StateStoreError.AlreadyExists`. |
| Non-mutation | The selected lock digest is unchanged by the repeat and the opposite lock remains absent. |
| Filesystem | No project `.agents`, home `.agents`, or `$HOME/.cache/c-plugin` is created. |

### Notes

- These sibling-source assertions do not certify a successful test run and do not independently assert stderr.
- The two public init cases are isolated even though they share the `runInitWorkflow` helper.

## `initGlobalScenario`

### Scope

Create the global lock exclusively and reject a repeated initialization without synchronization side effects.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Exclusively create the selected lock and reject a repeated initialization. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `-g` | Select the global lock on the initial command. |
| `--global` | Select the same global lock on the repeated command. |

### Preconditions and fixtures

- Each registered case receives its own `c-plugin-e2e:local` container.
- `HOME=/tmp/c-plugin-v2-init-e2e/home` and `PROJECT=/tmp/c-plugin-v2-init-e2e/totto2727-org/monorepo` are synthetic container paths.
- The helper creates HOME and PROJECT directories with no existing project/global lock, marketplace, cache, ownership state, or managed skill directory.
- `c-plugin` denotes `/sandbox/.local/bin/c-plugin`; argv is passed directly with `WorkingDir=$PROJECT` and the isolated HOME.

### Execution flow

1. Run `c-plugin init -g` from `$PROJECT`.
2. Check `Created <absolute selected lock path>\n`, the empty lock JSON at `$HOME/c-plugin-lock.json`, and the absence of `$PROJECT/c-plugin-lock.json`. Record the created lock digest.
3. Run `c-plugin init --global` from `$PROJECT`.
4. Verify nonzero status, the expected error substring, and an unchanged lock digest.
5. Check that neither project nor home `.agents` nor `$HOME/.cache/c-plugin` was created, and the opposite-scope lock remains absent.

### Expected results

| Observation | Expected result |
| --- | --- |
| Initial status/output | Exit 0; exactly `Created <absolute selected lock path>\n` in captured output. |
| Lock JSON | Exactly the JSON value `{"version":"2","targets":[],"repositories":[]}`; object key ordering is not asserted by the JSON helper. |
| Scope isolation | `$HOME/c-plugin-lock.json` exists and `$PROJECT/c-plugin-lock.json` is absent. |
| Repeated status/output | Nonzero exit; captured output contains `totto2727/c-plugin.StateStoreError.AlreadyExists`. |
| Non-mutation | The selected lock digest is unchanged by the repeat and the opposite lock remains absent. |
| Filesystem | No project `.agents`, home `.agents`, or `$HOME/.cache/c-plugin` is created. |

### Notes

- These sibling-source assertions do not certify a successful test run and do not independently assert stderr.
- The two public init cases are isolated even though they share the `runInitWorkflow` helper.
