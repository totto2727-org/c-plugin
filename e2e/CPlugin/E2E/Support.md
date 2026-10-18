# Shared E2E command and assertion support

Source: [Support.hs](./Support.hs).
This module exports its complete API for the sibling Hspec modules.
It uses only the public `Test.CLI.E2E` module.

## Scope

Provide shared command execution and assertions without a custom test runner or a second container lifecycle.
Each Hspec `it` owns its Caseyard `Environment` through `withEnvironment "c-plugin-e2e:local"`.
The caller builds the image once and runs Hspec with `--jobs=2`.

## Commands under test

| Command path | Purpose |
| --- | --- |
| `/sandbox/.local/bin/c-plugin` | Execute the actual CLI under test. |

## Arguments and options

`run s cwd argv` prepends the CLI executable and supplies `HOME` from `Scenario`.
`infra s cwd argv` executes infrastructure argv directly without adding `HOME`.
The `runWithEnv` and `infraWithEnv` variants accept explicit `(name, value)` environment entries before argv.
An empty working directory uses the image default.
No shell is used for these operations.

## Preconditions and fixtures

`Scenario` stores the public environment, synthetic home path, and one opaque `scenarioDriver`.
`newScenario env homePath` reads the trusted Linux driver bytes from the required host `C_PLUGIN_E2E_DRIVER` path and installs them once with `installDriver`.
The caller builds the driver for the container architecture before the suite starts.
The shared driver stays inside the owning environment callback and supports both snapshots and terminal sessions.
All container paths belong to disposable test fixtures.
`writeFile` creates parent directories and encodes text as UTF-8.
`readFile` returns strict bytes without newline conversion.

## Execution flow

1. Hspec leases a prebuilt image and opens an isolated environment for one example.
2. The example installs its driver through `newScenario` and creates its fixtures.
3. `run` executes CLI commands and returns the public `CLI.Result`.
4. Assertions compare exit status, captured streams, JSON values, bytes, physical path kinds, ownership records, and checksums.
5. Caseyard closes the environment when the example returns or throws.

## Expected results

| Helper | Contract |
| --- | --- |
| `requireSuccess`, `requireFailure`, `requireExit` | Assert zero, nonzero, or the exact exit code. |
| `requireOutput` | Compare exact stdout bytes after UTF-8 encoding the expected text. |
| `requireContains`, `requireNotContains` | Assert string substring presence or absence. |
| `captureSnapshot` | Capture selected physical entries with the scenario's public driver, including exact file and literal symlink bytes. |
| `requireFile` | Compare a public single-path snapshot to `RegularFile` with exact expected bytes. |
| `requireJSON` | Decode actual and expected bytes as Aeson `Value` and compare them structurally. |
| `digest`, `requireDigest` | Compute SHA-256 and compare the actual checksum bytes. |
| `pathExists`, `requireMissing` | Use public `pathKind` to distinguish physical absence from existing entries, including dangling symbolic links. |
| `requireRegularFile`, `requireDirectory` | Compare public `pathKind` values and reject symbolic links even when their targets have the requested kind. |
| `requireSymlink` | Require a symbolic link, then compare `realpath` stdout to the canonical expected target plus newline. |
| `requireOwnershipSkill` | Require an ownership object, validate each source tag and tuple length, then check whether the last source component matches the requested skill. |

## Notes

The canonical `realpath` assertion checks the resolved target; scenarios that require literal target identity compare public snapshots or explicit `readlink` output.
Ownership checks accept both three-component `OwnershipSource` and two-component `StandaloneSource` values.
SHA-256 assertions compare file checksums before and after an operation.
Infrastructure failures propagate as Caseyard exceptions or Hspec failures.
This document describes assertions, not evidence of an executed Docker run.
