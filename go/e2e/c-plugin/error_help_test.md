# Standard parser failure help

Source: [error_help_test.go](./error_help_test.go)

## `errorHelpScenario`

### Scope

Verify that missing commands, required arguments, and option values retain standard parser errors and display the complete help for the failed command context.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Create the isolated project lock before parser checks. |
| `c-plugin` | Check a missing top-level command. |
| `c-plugin plugin` | Check a missing plugin command. |
| `c-plugin skill` | Check a missing skill command. |
| `c-plugin skill target` | Check a missing target command. |
| `c-plugin plugin add` | Check a missing source and source or selection option values. |
| `c-plugin skill add` | Check a missing standalone source. |
| `c-plugin skill target add` | Check a missing positional target. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--help` | Obtain the standard complete help for each failing context. |
| `--ref` | Trigger a missing GitHub ref option value. |
| `--skill` | Trigger a missing selection option value after `local:./plugin`. |
| `PATH` | Required target-add argument. |

### Preconditions and fixtures

A fresh container uses `HOME=/tmp/c-plugin-error-help-e2e/home` and `project=$HOME/project`.
The helper invokes the real `/sandbox/.local/bin/c-plugin` binary with direct argv and isolated HOME.
The project contains an initialized lock, without any plugin registration or managed skill root.

### Execution flow

1. Create HOME and project directories, initialize the project lock, and save its digest.
2. For each of nine missing-command, argument, or option-value cases, invoke the matching command context with `--help`.
3. Invoke the malformed command and compare its output with the entire successful help output.
4. Confirm the standard error text, nonzero exit status, and unchanged lock digest after every case.
5. Confirm that neither project nor HOME gained an ownership directory or global lock.

### Expected results

Every `--help` invocation exits 0 and contains `Available options:`.
Each malformed invocation exits 1, retains its standard missing-command, missing-argument, or option-value error, and contains the entire context-specific help output.
The project lock digest stays unchanged throughout the nine cases.
No global lock or project/global `.agents` directory is created.

### Notes

The renderer is the standard optparse-applicative `showHelpOnError` preference applied to Iris's public parser.
The test compares actual help output rather than maintaining a separate shortened usage string.
