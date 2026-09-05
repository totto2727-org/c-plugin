# Documentation-first migration ledger

## Provenance and scope

- Initial template main: [`59e26443637d9af694eb34ed008a5592f8c45027`](https://github.com/totto2727-org/c-plugin/tree/59e26443637d9af694eb34ed008a5592f8c45027).
- Preserved raw v2 snapshot: [`5d6f66a83be6ed23d16d3c8535722970e028a003`](https://github.com/totto2727-org/c-plugin/tree/5d6f66a83be6ed23d16d3c8535722970e028a003).
- Original integrated source: [`feed20ebe00a618c06c20d4996bbe9d1dd657029`](https://github.com/totto2727-org/monorepo/tree/feed20ebe00a618c06c20d4996bbe9d1dd657029).
- Documentation stage: [TOT-198](https://linear.app/totto2727/issue/TOT-198).
- Migration parent: [TOT-197](https://linear.app/totto2727/issue/TOT-197).

The raw snapshot was saved before documentation review corrections.
The first product PR adds documentation and documentation aliases only, relative to the template main.
The template sample, manifests, Nix definitions, and workflows may already exist on that main, but this layer adds no c-plugin implementation, Go test source, Dockerfile, task definition, dependency, or test stub.
Old c-plugin/v1 source, skill instructions, ADRs, and reports are not migrated.
Lock version `"2"` is unchanged; moving repositories does not implement lock conversion.
The inherited MIT file is preserved, not used as evidence that the migration has independently audited every upstream code license.
Licensing and actual package availability must be checked before product publication.

## Feature stage map

Every feature layer is based on this S0 documentation commit and includes its applicable implementation and tests.
The map records planned migration order, not completed or released functionality.

| Stage | Scope |
| --- | --- |
| S0 | Documentation baseline and preserved contracts |
| S1 | Native bootstrap and independent execution/packaging infrastructure |
| S2 | Runtime paths, lock and ownership domain values |
| S3 | Strict lock and ownership codecs |
| S4 | Cache identity |
| S5 | Lock discovery |
| S6 | State persistence |
| S7 | Runtime composition and init |
| S8 | Marketplace parsing and local resolution |
| S9 | Desired-link planning |
| S10 | Ownership-safe filesystem reconciliation |
| S11 | Local and recursive sync |
| S12 | Persist-and-sync mutation boundary |
| S13 | Local add |
| S14 | Target add |
| S15 | Skill remove |
| S16 | Target remove |
| S17 | Bit adapter, not GitHub leaf workflows |
| S18 | Final parity/review gate, not an additional implementation PR |

The original complete add scenario invokes remove and force in addition to add.
Do not run that full scenario before its dependency-bearing layers exist or add a fake remove implementation merely to make S13 pass.
Its complete existing workflow becomes eligible at S15, while earlier add coverage must remain truthful about its smaller dependency scope.
Each layer must record which real scenarios were run and update links/status when its sources are introduced.

## Current and planned behavior

The [saved capability table](./cli.md#capability-status) separates source present in the raw snapshot from missing GitHub lifecycle, interactive input, and marketplace-authoring workflows.
The broader design is an intended contract, not evidence that every milestone is implemented.
[TOT-121](https://linear.app/totto2727/issue/TOT-121) explicitly requires duplicate repository/plugin/skill rejection.
This migration preserves that behavior and corrects the older blanket no-op/merge wording.
[TOT-157](https://linear.app/totto2727/issue/TOT-157) authorizes precise filesystem replacement, not same-source force-repeat synchronization.
Union merge and new force-repeat behavior are not introduced by this documentation change; their unstarted follow-up is [TOT-224](https://linear.app/totto2727/issue/TOT-224).
Supported target-add and remove no-ops remain separate existing contracts.

## Source links across layers

Scenario documents are placed under `go/e2e/c-plugin/`, beside the eventual Go sources.
In a layer where the corresponding Go source is absent, Source links use the complete raw SHA above; after source introduction, they use the actual relative sibling link.
They refer to real immutable saved files, not nonexistent relative targets or mutable branch contents.
When introducing a source file, restore its document's `[name_test.go](./name_test.go)` link and validate the pair in the real directory.
Keep the raw provenance reference available for comparison.
The initial `initScenario` helper is documented as a helper, not a ninth case; a later helper rename must remove or update its section at the same time.

## Documentation validation

The S0 documentation baseline contains seven E2E documents for eight registered cases.
Its pinned raw Go source contains nine functions ending in `Scenario` because init's shared helper also matches that naming rule.
The S0 init document therefore has three complete sections, explicitly distinguishing two registered cases from the shared helper.
The reviewed source renames that helper to `runInitWorkflow`; after all owning layers introduce the reviewed sources, the suite has eight `Scenario` functions and init has two documented sections.
Each other scenario document has one section in both variants.
This historical S0 projection description does not replace validation against the source files actually present in a feature layer.

Use the validator shipped with the `document-e2e-scenarios` skill and the [current E2E documentation contract](https://github.com/totto2727-org/e2e/pull/8).
For the historical source-free S0 layer:

1. Export the exact pinned Go sources into a disposable directory outside the committed tree.
2. Copy these seven documents into that directory and check each original Source URL against the pinned SHA and file path.
3. Only in the disposable copies, project the Source URL into the conventional relative sibling link.
4. Run `python3 <skill-directory>/scripts/validate_scenario_docs.py <disposable-directory>` and inspect every scenario against its Go source, helper, and fixture.
5. Record this as source-backed projection validation, not a normal in-tree validator pass or an E2E execution.

A validator run that sees zero Go files is not evidence of coverage.
Once a feature layer introduces the sources, run the validator on the actual source/document directory without projection, then run the real Go/Testcontainers workflows separately.
Expected results in these documents describe assertions in the saved source; they are not test-run reports.

### MoonBit example policy

The preserved v2 README contains bash examples but no MoonBit code fences.
This layer introduces no `mbt check`, plain `mbt`, or `mbt nocheck` block and adds no compilation-only package or stub.
There are zero disabled examples to re-enable.
If a future documentation extraction includes an example whose API is not introduced yet, mark that specific block `mbt nocheck` and add a row recording its document/heading, API dependency, owning stage, and exact re-enablement check.
The implementing layer must restore `mbt check` and show that the exact artifact was compiled or tested.
A zero-work or template-only `moon check` / `moon test` result does not validate product examples.
See [MoonBit's official documentation](https://docs.moonbitlang.com/en/latest/language/docs.html).

## Review constraints retained

- Strict complete `FromJson` models, single discriminator dispatch, canonical collections, and normalized path values remain required.
- Preserve literal `symlinkTarget` identity independently from resolved path normalization, including raw traversal/backslash rejection at the owning boundary.
- Preserve [ownership durability](https://github.com/totto2727-org/monorepo/pull/274): trusted/missing/corrupt state distinctions, checkpoint failures, no automatic adoption, and the unguaranteed crash window between filesystem mutation and checkpoint.
- Preserve [force containment](https://github.com/totto2727-org/monorepo/pull/321): exact non-directory replacement only, post-create verification, and directory/neighbor protection.
- Preserve [mutation sequencing](https://github.com/totto2727-org/monorepo/pull/312): absent/equal candidates do not write or sync, and successful persistence passes the same candidate to sync.
- Preserve [typed path identity](https://github.com/totto2727-org/monorepo/pull/322) and pinned native dependency compatibility rather than restoring obsolete workspace packages.
- Treat the [bit adapter](https://github.com/totto2727-org/monorepo/pull/326) as an adapter milestone only.
- Keep Go/Testcontainers, fixtures, module checksums, lint/task configuration, Dockerfile, caller-owned image, and separate CI execution in the feature stack.
- GitHub fixture selection and successful network lifecycle tests must be established by the corresponding future workflow; the eight local cases are not GitHub coverage.

Product source fixes, Docker/Nix optimization, typed-error adoption, full runtime tests, and publication are validated in their owning feature layers.
This documentation-only PR cannot certify those implementation results.
