# c-plugin 設計契約

この文書はv2再実装の設計契約を独立製品`c-plugin`へ保存するものです。
すべての計画コマンドが実装済み・公開済みという意味ではありません。
実装済み機能と計画の区別は[機能の状態](../cli.md#capability-status)を参照してください。

[English contract](./contract.md)。
出典: [raw migration snapshot `5d6f66a8`](https://github.com/totto2727-org/c-plugin/blob/5d6f66a83be6ed23d16d3c8535722970e028a003/docs/design/contract.ja.md)。

## 提供状態と識別子

独立製品のexecutableは`c-plugin`、MoonBit source moduleは`totto2727/c-plugin`、repositoryは`totto2727-org/c-plugin`です。
これらのsource上の識別子はregistry公開済みの意味ではありません。
設計書は`docs/design/`、保存したnative packageは`src/`、Go/Testcontainers E2Eは`go/e2e/c-plugin/`に配置します。
v1および旧ADRは移植せず、旧契約を現行仕様として使用しません。
v1 lock変換、自動migration、`migrate` commandは提供しません。
旧版と新版を同じlock scopeへ実行してはいけません。

raw snapshotにはinit、local add/remove/sync/recursive sync、target add/removeが配線されています。
bit adapterは存在しますが、GitHub add/update/cache、TTY対話、marketplace authoringのleaf機能は未実装です。
以下の該当契約は計画として保持し、[GitHub lifecycle](https://linear.app/totto2727/issue/TOT-218)、[TTY](https://linear.app/totto2727/issue/TOT-219)、[authoring](https://linear.app/totto2727/issue/TOT-220)、[full parity](https://linear.app/totto2727/issue/TOT-221)で追跡します。
包括的な冪等性・unionは[TOT-224](https://linear.app/totto2727/issue/TOT-224)の未実装目標であり、採用済みlocal addのduplicate拒否を上書きする保証ではありません。

## 目標

- 現在のユーザー向け機能を維持しながら、c-pluginをMoonBitで再実装する。
- 将来拡張可能なリソース名前空間を中心にコマンド体系を整理し、現在のMoonBit移植版より前に存在していた対話的な選択を復元する。
- 型付きパス、厳格なロックファイルのデコード、ライブラリによるGit操作、決定論的なテストを最初から採用する。
- プロジェクトとグローバルを分離する。`init`以外を包括的に冪等化することは目標であり現在の保証ではなく、local addはduplicate identityを拒否する。

機能的な等価性には、公開された`c-plugin skill`名前空間の維持を含めます。内部関数は再設計して構いません。

## 技術スタック

| 対象             | 方針                                                                                                                                   |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| 言語とターゲット | MoonBit、nativeターゲットのみ                                                                                                          |
| CLI解析          | `totto2727/admiral`                                                                                                                    |
| 対話入力         | `mizchi/tui`は将来のTTY機能向け候補であり、c-pluginの直接依存には含めない。Admiral経由の推移依存は残る                                                                                                                           |
| Git              | `mizchi/bit`モジュールをライブラリとして使用し、主に`mizchi/bit_lib`などのライブラリパッケージを利用する。`git`や`bit` CLIは起動しない |
| パス             | filesystem境界では`moonbitlang/x/path.Path`、検証済みdomain値では`totto2727/x@0.3.0/path.AbsolutePath`と`RelativePath`                 |
| ロック探索       | `totto2727/admiral/util/target-file-discovery`                                                                                                      |
| JSON             | `totto2727/lens`と標準の`FromJson`、`ToJson`トレイト                                                                                   |
| 非同期I/O        | `moonbitlang/async`                                                                                                                    |
| 単体テスト       | テストごとの一時ルートを使用するMoonBitブラックボックス・ホワイトボックステスト                                                        |
| E2Eテスト        | Go/Testcontainersによる制御、fixture、assertion、シナリオごとの独立container                                                           |

採用した依存関係は、互換性を確認した正確なバージョンに固定します。
Admiral内蔵の探索パッケージを使用し、独立した探索モジュールは追加しません。
互換性は製品のnativeビルドと動作テストで検証し、依存ライブラリ単体のprobeは維持しません。
TTY依存は対話機能を実装するときに追加し、製品の振る舞いを通して検証します。

`mizchi/bit`は現在、自身を実験的実装と説明し、リポジトリ破損の可能性を警告しています。そのため、c-pluginではキャッシュしたcloneを破棄可能なデータとして扱い、依存バージョンを固定し、使用するclone、fetch、checkout、HEAD解決APIを正確にテストします。

## 計画上のコマンド体系

スキル管理は引き続き`skill`名前空間に配置します。これにより、将来的に`hook`や`mcp`などのトップレベルリソース名前空間を追加できます。インストールコマンドと分離するため、作者向けのマーケットプレイス変換は`dev`以下に残します。

```text
c-plugin
├── init
├── skill
│   ├── add
│   ├── remove
│   ├── sync
│   ├── update
│   └── target
│       ├── add
│       └── remove
└── dev
    └── marketplace
        └── sync
```

以下は全体の計画契約です。保存済み実装で配線されている範囲は冒頭の提供状態と識別子で区別します。

| コマンド                                                                                                                 | 契約                                                                                                                                                                                                                                                                                                    |
| ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `c-plugin init [-g]`                                                                                                     | 空のロックファイルを排他的に作成する。すでに存在する場合は変更せず失敗する。                                                                                                                                                                                                                            |
| `c-plugin skill add [<owner/repo> \| --local <./path>] [-g] [-f \| --force] [--kind <kind>] [--skill <plugin/skill>...]` | GitHubまたはローカルのマーケットプレイスを追加し、マーケットプレイス種別と有効化するスキルを選択し、GitHubの状態を固定し、ロックを書き込んでリンクを同期する。GitHubの位置引数と`--local`のどちらか一方だけを受け付ける。forceはcontainment確認済みの通常ファイルとシンボリックリンクの衝突を置換する。 |
| `c-plugin skill remove [-g] [--skill <repo/plugin/skill>...]`                                                            | 選択したインストール済みスキルを削除する。最後のスキルを削除した後に、空になったプラグインエントリ、空になったリポジトリエントリ、破棄可能なGitキャッシュを削除する。                                                                                                                                   |
| `c-plugin skill sync [-g \| -r]`                                                                                         | Gitの固定状態を変更せず、ロックの状態から管理対象リンクを調整する。                                                                                                                                                                                                                                     |
| `c-plugin skill update [-g \| -r]`                                                                                       | GitHubリポジトリをfetchし、固定状態を進め、ロックを書き換えてリンクを同期する。ローカルリポジトリはfetchしない。                                                                                                                                                                                        |
| `c-plugin skill target add <path> [-g]`                                                                                  | 追加のスキルリンクルートを登録して同期する。解決後のパスが重複している場合は正常なno-opとする。                                                                                                                                                                                                         |
| `c-plugin skill target remove [-g] [--target <path>...]`                                                                 | 選択した追加ルートをロックの状態から削除し、そのルートからc-plugin管理下のリンクだけを削除する。                                                                                                                                                                                                        |
| `c-plugin dev marketplace sync <claude\|cursor\|codex>`                                                                  | 選択したマーケットプレイス種別を入力元として、他のマーケットプレイスmanifestと、存在するプラグインごとの`plugin.json`を再生成する。                                                                                                                                                                     |

`-g`と`-r`は同時に指定できません。再帰モードは`sync`と`update`だけに適用します。

### 対話入力と非対話入力（計画、未実装）

以下のTTY選択は保存済みsnapshotでは未実装の計画です。stdinがTTYであり、明示的な選択オプションが省略されている場合、`mizchi/tui`が選択UIを提供します。

- `skill add`は、対応する種別が複数存在するとき、マーケットプレイス種別の単一選択を表示する。
- `skill add`は`plugin/skill`エントリの複数選択を表示し、すでに有効なスキルを事前選択する。
- `skill remove`はインストール済みの`repository > plugin/skill`エントリの複数選択を表示する。
- `skill target remove`は登録済みの追加ターゲットディレクトリの複数選択を表示する。

stdinがTTYでない場合は、対応する`--kind`、繰り返し可能な`--skill`、または繰り返し可能な`--target`オプションを必須とします。非対話実行では、すべての項目を暗黙に選択したり、対話ユーザーが通常選択する既定値を暗黙に受け入れたりしません。

キャンセルと空の選択は正常なno-opとし、ロックファイルを書き換えません。

TUIは選択状態を扱うアダプターであり、コマンドのビジネスロジックには含めません。コマンドハンドラーは型付きの選択結果を受け取るため、単体テストでは実端末を操作せずに決定論的な選択を注入できます。

## 機能等価性の基準

次の機能を維持した時点で再実装完了とします。

- `owner/repository`形式で記録するGitHubマーケットプレイスソースと、`./`から始まるローカルマーケットプレイスソース。
- Claude、Cursor、Codexマーケットプレイスの検出と解析。
- 検出されたすべてのスキルの暗黙インストールではなく、プラグインごとの明示的なスキル有効化。
- GitHub commitの固定と、固定したcommitでの再現可能な同期。
- リモートのデフォルトブランチへの更新と、それに続くロックとリンクの更新。
- `.agents/skills`以下の主リンクと、0個以上の追加リンクターゲット。
- 最も近い親のプロジェクトロック探索、home直下のグローバルロック探索、再帰的な子孫ロック探索。
- `totto2727/admiral/util/target-file-discovery`による`.gitignore`を考慮した再帰探索。
- 複数リポジトリ同期の耐障害性。1つのリポジトリが利用できない場合は報告してスキップし、独立した他のリポジトリの同期を妨げない。
- JSON入力順や内部collectionの反復順に依存せず、同期時にcanonical repository順で最後のリポジトリを採用する決定論的なスキル名重複解決。
- Claude、Cursor、Codex形式間のマーケットプレイス変換。
- 正規化された`./plugins/...`パスと`policy.installation = "INSTALLED_BY_DEFAULT"`を持つCodexのローカルsource object。
- 入力元種別のプラグインに`plugin.json`が存在する場合、対象種別へコピーする。

新しいロック形式はv1とは別にバージョン管理します。機能等価性には、不正なv1ドキュメントの受け入れや寛容なデコーダーの不具合の維持は含みません。

現時点の実装では、ロックmigrationを明示的に対象外とします。c-plugin v2は自動migrationも`migrate`コマンドも提供せず、decoderが旧versionをv2として再解釈してはいけません。既存ロックが未対応versionを宣言している場合、そのロックを読み込むすべてのコマンドはロックを書き換えず、link、cache、ownership stateも変更せずに失敗します。`init`も既存ロックを置換せず、従来どおり拒否します。

将来、明示的な承認を受けた独立マイルストーンとしてmigration経路を追加しても構いません。その場合はversion間の変換規則、atomicな永続化、書き込み成功後の同期、専用の単体テストとE2E coverageを持つ明示的な操作とし、通常のロックdecode内の寛容なfallbackとして追加してはいけません。最上位のlock versionを必須のまま維持することで、現時点ではmigrationを実装せずに将来の拡張点を残します。

## スコープとパスの規則

ロックファイル名は`c-plugin-lock.json`のまま維持します。

| スコープ           | ロックパス                                                                  | 主な管理対象スキルルート |
| ------------------ | --------------------------------------------------------------------------- | ------------------------ |
| プロジェクト       | ユーザーのhomeを境界として探索した最も近い祖先の`<root>/c-plugin-lock.json` | `<root>/.agents/skills`  |
| グローバル（`-g`） | 厳密に`~/c-plugin-lock.json`                                                | `~/.agents/skills`       |

グローバルロックファイルは意図的に`~/.agents/`以下へ配置しません。

`init`は現在の作業ディレクトリをプロジェクトルートとして使用し、`-g`では注入されたhomeディレクトリを使用します。その他のスコープ付きコマンドはすべて、`totto2727/admiral/util/target-file-discovery`で既存のロックを探索し、別のルートを推測しません。

再帰探索は、最も近いプロジェクトロックを含むディレクトリから開始し、そのロックと子孫のロックを含みます。グローバルモードでは再帰探索を行いません。

キャッシュルートは既定で`~/.cache/c-plugin/repositories`とし、テストでは実行時境界から差し替えられるようにします。キャッシュの内容は正とせず、ロックファイルを正とします。

### キャッシュIDとロックの分離

リポジトリキャッシュは、それを所有するロックファイル単位でスコープを分離します。2つのプロジェクトロックが同じGitHubリポジトリを異なるcommitに固定する可能性があるため、owner/repositoryだけのキャッシュキーは禁止します。

ロックパスを絶対`Path`へ正規化した後、キャッシュのスコープキーを次のように導出します。

```text
scope_key = lowercase_hex(sha256(utf8("lock\0" + normalized_absolute_lock_path)))
cache_path = cache_root / scope_key / lowercase(owner) / lowercase(repository)
```

完全な64文字のSHA-256 digestを使用し、言語runtimeのhash値や短縮digestは使用しません。プロジェクトモードでは探索済みの絶対プロジェクトロックパスをhash入力とし、グローバルモードでは注入されたhomeディレクトリ以下の絶対`~/c-plugin-lock.json`パスをhash入力とします。

各スコープディレクトリには、format versionとhash入力に使用した正確な正規化済み絶対ロックパスを記録する生成metadata、`c-plugin-cache-scope.json`を配置します。ディレクトリを再利用する前に、c-pluginはそのmetadataを厳格に検証しなければなりません。記録が存在しない場合や一致しない場合はディレクトリを共有せずエラーとするため、digestの衝突や手動でコピーされたcacheによって2つのロックスコープが暗黙に統合されることはありません。

GitHubのownerとrepository componentは、それぞれのdomain constructorで検証し、スコープパスへ結合する前に小文字へcanonicalizeします。未解析の`owner/repository`入力を1つのパス文字列として追加してはいけません。GitHubは両方のroute componentで大文字と小文字を区別しないため、大小文字だけが異なる入力を同じIDへ変換することを意図しています。

この規則により、次の動作となります。

- 1つのロック内で同じリポジトリを参照する場合、1つのcacheと固定済みworking treeを共有する。
- 異なるプロジェクトロックまたはグローバルロックは、同じリポジトリを参照しても異なるcacheを使用し、checkout、update、削除によって別のロックが生成したskillを変更しない。
- cache変更はowner/repositoryだけではなく、スコープを含む完全なcache `Path`単位で直列化する。
- あるロックから最後の参照を削除した場合、そのロックにスコープされたリポジトリcacheだけを削除してよい。
- プロジェクトを移動すると正規化済みロックパスが変わるため、スコープキーも変わる。古いcacheは破棄可能な孤立dataとし、新しいスコープが暗黙に採用してはならない。

### パスの型付け

- CLI文字列、環境変数文字列、JSON文字列は、それらを所有する境界ですぐに`Path`へ変換する。
- コマンド、アプリケーション、探索、ロック、ファイルシステム、キャッシュ、マーケットプレイス、シンボリックリンクのロジックでは`Path`を受け渡す。
- MoonBit非同期ファイルシステム呼び出し、LensのJSON encoding、現在のbit APIなど、文字列を要求する末端のライブラリ呼び出しでのみ`Path`を`String`へ変換する。
- GitHubリポジトリは制約のないパス風文字列ではなく、検証済みの`GitHubRepository { owner, name }`として表現する。
- 相対ローカルマーケットプレイスパスとターゲットパスは、constructorが制約を保証する型付きドメイン値として保持する。
- パスは比較前に正規化する。ユーザーが入力したパス表記を直接比較しない。

`totto2727/admiral/util/target-file-discovery`は現在、文字列ベースのpublic関数を公開しています。その変換は1つの探索アダプターに閉じ込め、型なしパスをc-pluginの他の領域へ漏らしません。後からこのライブラリにPathベースAPIを追加しても構いませんが、別の探索実装を作るための必須条件とはしません。

## Git方針

- 保存済みsourceが使用する`mizchi/bit_lib`、`mizchi/bit_object`、`mizchi/bit_osfs`を固定し、そのAPIを直接呼び出す。
- Git操作に`moonbitlang/async/process`を使用せず、インストール済みの`git`や`bit`実行ファイルへフォールバックしない。
- 1つの狭い`BitRepositoryStore`アダプターを通じて、HTTPS GitHub clone、fetch、デフォルトブランチ解決、固定commitのcheckout、HEAD object ID解決を提供する。
- bitが現在要求する文字列パスはそのアダプター内部だけで扱い、c-plugin向けpublic APIは`Path`と型付きobject IDを受け渡す。
- リポジトリは、上で定義した決定論的なロックスコープ付きキャッシュパスに保存する。
- 同じキャッシュリポジトリを操作する変更は直列化する。独立した読み取り専用の解決は並行実行してよい。
- ユーザーのソースリポジトリにworking tree変更を適用しない。すべてのGit変更は破棄可能なc-pluginキャッシュディレクトリだけで行う。

## ファイルシステムと冪等性の方針

`init`によるロック作成だけを排他的な作成操作とします。既存のロックファイルを上書きしてはいけません。

既存directoryと各commandのno-opは以下の規則に従います。これはすべての非`init`再実行が成功するという包括的保証ではありません。

- 期待する既存ディレクトリを受け入れる。
- local addは既存repositoryの再登録を含むduplicate repository/plugin/skillを永続化前に拒否する。skill unionやforceによる同一sourceのsync-onlyは追加しない。[TOT-121](https://linear.app/totto2727/issue/TOT-121)の採用済み契約を維持する。
- 正規化済みtargetの再登録、および文書化されたempty/unknown/repeat removeは個別の正常no-op契約を維持する。
- c-pluginが管理する既存ファイルとシンボリックリンクは、ロックに従って更新または削除してよい。
- デフォルトでは、出力先にある管理外ファイル、ディレクトリ、または管理外シンボリックリンクは変更せず、スキップしたことを報告する。
- `skill add -f`または`skill add --force`は、containment確認済みのdesired output pathと完全一致する通常ファイルまたはシンボリックリンクだけを置換できる。実ディレクトリ、特殊path、neighbor、managed root外のpathは削除しない。
- Syncでディレクトリ全体を消去せず、c-pluginの管理対象と判明しているリンクだけを削除する。
- マーケットプレイス生成では、自身の対象manifestとコピー済み`plugin.json`を置換してよいが、既存ディレクトリの無関係なファイルは削除しない。

### シンボリックリンクの所有state

シンボリックリンク自体には、作成したprocessを識別できる信頼性のあるmetadataがありません。ロックは共有可能な望ましい状態を記録するため、他者がロックを変更した後に古くなったリンクを、ロックだけから識別することはできません。そのため、c-pluginは生成したリンクについて、ロックとは別にmachine-localな所有stateを維持します。

| スコープ           | 所有stateのパス                      |
| ------------------ | ------------------------------------ |
| プロジェクト       | `<root>/.agents/c-plugin-state.json` |
| グローバル（`-g`） | `~/.agents/c-plugin-state.json`      |

所有stateは生成されたruntime stateであり、共有設定でも、望ましい状態を表す第2のsource of truthでもありません。各entryには、絶対link path、シンボリックリンクへ書き込んだliteral target、正規化済みresolved target、source repository、plugin、skill identityを記録します。後からロックから削除されたtarget root内のリンクも維持します。

`sync`は望ましいロックと以前の所有stateを次のように調整します。

1. ロックと所有stateの両方を読み込み、厳格に検証する。
2. ロックから望ましいリンクを計算し、`以前の所有link - 望ましいlink`から古いリンクを計算する。
3. stale pathを削除する前にsymlink kind、記録されたresolved target、managed-root containment、ownership identityを検証する。literal `symlinkTarget`を別identityへ正規化しない。
4. pathがfile、directory、または別のsymlinkへ置き換えられている場合は変更せず、所有権を失ったことを報告し、次の所有stateから除外する。
5. 事前に存在する未記録のsymlinkは、現在のresolved targetが望ましいtargetと一致していても自動的に採用しない。
6. 不足している望ましいリンクを調整し、各filesystem mutationの後にstateをcheckpointする。新規作成したlinkはpost-create verificationとcheckpointの両方が成功した後にのみ永続的な所有stateへ登録する。checkpointが失敗した場合は成功とせず、処理を停止して失敗を報告する。

このstateは外部からのロック変更後も残るため、後から`c-plugin skill sync`を実行すると、削除されたskillやtarget登録に対応するリンクを削除できます。所有権はロックごとに分離し、recursive syncで別のロックが所有するリンクを削除してはいけません。

安全規則は次のとおりです。

- 所有stateが存在しない、または壊れている場合、既存リンクの削除を無効にする。衝突しない不足リンクを作成して新しいstateを開始してよいが、scanによる所有権の推測や自動採用を行わない。
- 所有stateから読み込んだすべてのpathは、filesystemを変更する前に、記録済みmanaged rootに含まれることを検証する。
- 現在のpublic `moonbitlang/async/fs` APIはsymlinkを考慮する`kind`と`realpath`を公開していますが、literalな`readlink`値を公開していないため、壊れたsymlinkのtargetを検証できない。そのようなリンクは変更せず報告する。壊れたリンクのcleanupが必要になった場合は、後から小さな`readlink` filesystem adapterを追加してよい。
- 所有stateの書き込みには同じディレクトリの一時ファイルとatomic renameを使用する。所有stateの書き込みによって`sync`を再帰的に起動しない。`sync`を起動するのはロック変更だけとする。
- 破棄可能なGit cacheは、古い管理対象リンクを調整した後に削除し、リンク削除時にtargetを検証できる状態を維持する。

### ロック変更の不変条件

既存ロックファイルの変更が成功した場合、コマンドが終了する前に、永続化したロックの値と完全に同じ値を使用して通常の`sync`調整を必ず実行します。この規則はrepository、plugin、enabled skill、target、marketplace kind、commit pin、および将来追加するresourceの変更に適用します。

- `init`は既存ロックの更新ではなく新しい空ロックを作成するため、唯一の例外とする。
- キャンセルまたは意味的なno-opとなるコマンドはロックを書き込まず、`sync`も不要とする。
- コマンドworkflowは1つの`persist_and_sync` application boundaryを使用し、lock writerを直接呼び出して調整せずに終了してはならない。
- 永続化が成功した後に`sync`が失敗した場合、コマンドは非0 statusを返し、`c-plugin skill sync`の再実行によって永続化済み状態を調整できることを報告する。
- 再帰操作では、変更する各ロックにこの不変条件を個別に適用する。

ロック書き込みには同じディレクトリの一時ファイルと、その後のatomic renameを使用します。メモリ上の候補は永続化前に完全に検証します。ロック変更は次の順序で行います。

1. 完全な候補状態を解決して検証する。
2. ロックをatomicに書き込む。
3. 管理対象リンクと破棄可能なキャッシュ状態を調整する。

手順2より前の失敗では以前の状態を維持します。手順2より後の失敗は`sync`の再実行で復旧可能にします。


### Durabilityとliteral identityの補足

filesystem mutationとdurability checkpointの間のcrashについて、自動復旧やownership adoptionは保証しません。
未記録の既存linkは目的targetと一致しても自動adoptionしません。
`symlinkTarget`は保存したliteralを保持し、正規化したresolved targetとは別identityとしてconstructor/codecでround-tripします。
所有権stateはmutation後にcheckpointし、checkpoint失敗後に成功表示や後続mutationを継続してはいけません。

## ロックファイルモデル

v2ロックは厳格に扱い、データを持つEnum variantには最上位のdiscriminatorを使用します。

```json
{
  "version": "2",
  "targets": ["~/.claude/skills"],
  "repositories": [
    {
      "type": "github",
      "repository": "totto2727-org/agent",
      "marketplaceKind": "claude",
      "commit": "0123456789abcdef0123456789abcdef01234567",
      "plugins": [
        {
          "name": "symphony",
          "path": "plugins/symphony",
          "enabledSkills": ["commit"]
        }
      ]
    },
    {
      "type": "local",
      "path": "./",
      "marketplaceKind": "codex",
      "plugins": []
    }
  ]
}
```

JSONの規則は次のとおりです。

- 必須のlock `version`は厳密な文字列`"2"`としてエンコードする。binary floating-point parsingではprecision-sensitiveなversion tokenを厳密な検証のために維持できないため、JSON numberは受け付けない。
- すべてのロックフィールドをLensで定義する。
- Lensで選択した値は、Lensから導出した`JsonPath`を渡して標準の`FromJson`でデコードする。
- 標準の`ToJson`、Lensの`JsonBuilder`、`set_or_abort`でエンコードする。
- `LockRepository`のデコードでは、最上位の`type`を一度読み取ってから、完全な`github`または`local` payload decoderへ委譲する。
- `LockRepository`のエンコードでは、Enumを一度だけmatchし、variant object全体を出力する。
- `commit`、`repository`、`path`の有無からvariantを推測せず、propertyごとに個別の分岐を行わない。
- `MarketplaceKind`のようなscalar closed enumは、厳格な文字列表現を使用してよい。
- 必須フィールドの欠落、未知のEnum値、不正な型、不正なパス、無効なリポジトリ名、identityの重複、未対応バージョンはエラーとする。
- 壊れたJSONを空のロックとして扱ったり、不正なリポジトリエントリを暗黙に除外したり、不正な値を寛容な既定値へ置き換えたりしない。
- 一意なaggregateはimmutable hash set/mapに保持し、JSON入力順を内部状態に残さない。順序が必要な境界だけでsortし、canonical JSONではcode unitの辞書順を用いて、targetを正規化path、repositoryをsource kindとidentity、pluginをname、enabled skillをname、ownership entryを正規化link pathで並べる。

ロックcodecには、canonical encodingをデコードすると同じドメイン値へ戻るという1つのround-trip propertyを持たせます。整形出力は2スペースindentと末尾の改行を使用します。

## 概念上の内部構造

保存済み実装は`src/`の単一executable packageと対応white-box file群です。以下は責務の概念図であり、実在directoryや新package分割の要求ではありません。

実装は小さく保ち、大規模なframeworkではなく明示的な境界アダプターを使用します。

```text
src/
├── cli/            Admiral command definitions and argv-to-domain parsing
├── interaction/    mizchi/tui selection views and pure selection state
├── command/        Add, remove, sync, update, target, init, and dev workflows
├── domain/         Lock, repository, marketplace, skill, target, and validated identifier types
├── adapter/        Lens lock and ownership-state stores, target discovery, bit Git, async filesystem, and symlinks
├── e2e/            callerがビルドするE2E image用Dockerfile
└── main/           Executable entry point
```

直接的な関数と、注入が必要な箇所の小さなcallback recordを使用します。テストで利用する実際の外部境界を置き換えない限り、service、repository、trait layerを作りません。

## 単体テスト方針

単体テストは必須とし、通常のMoonBitテストコマンドで実行します。

- テストごとに新しい一時ルートを作成し、テスト後に削除する。
- 仮のhome、working directory、lock、`.agents`、cache、marketplace、target directoryをすべて一時ルート以下に置く。
- 実行時パスを注入し、テストから実ユーザーのhome、working tree、cache、global lock、global skill targetを読み取らない。
- 仮のhomeを使用して`-g`をテストする。分離できないプラットフォーム固有のcaseだけ省略できるが、その理由を該当テストsuiteの近くに記録する。
- 単体テストでbitを使用する場合は、一時ルート以下の破棄可能なリポジトリだけを操作する。
- lockのround trip、厳格な失敗、最上位Enum dispatch、canonical ordering、JSON error pathをテストする。
- 未対応のlock versionが、ロックの正確なbytesを維持し、link、cache、ownership stateを変更しないことをテストする。
- Pathの正規化、project/global/recursive discovery、local sourceの制約、targetの重複排除、ロックスコープキーの導出、スコープmetadataの生成とcodec検証、同じリポジトリを異なるcommitに固定する2つのロック間のcache分離をテストする。永続化したmetadataを利用するcache storage adapterを追加する時点で、metadata不一致の拒否をテストする。
- 純粋なTUI selection stateをテストし、command testにはscripted selectionを注入する。
- 冪等なコマンド再実行、管理外パスとの衝突、管理対象リンクの置換、skill重複時の優先順位、一部リポジトリの失敗、永続化前の状態維持をテストする。
- 既存ロックを変更するすべての経路が永続化した候補を`sync`へ渡し、`init`、キャンセル、意味的なno-opでは不要な調整を実行しないことをテストする。
- 外部からのロック変更、削除済みtarget root、置換済みlink、欠落または破損したstate、壊れたsymlink、recursive sync対象ロック間の分離について、所有stateによるcleanupをテストする。
- テストファイル名は、対象とする実装ファイル名に合わせる。

## E2Eテスト方針

E2Eテストは必須とします。image setup、fixture、command execution、assertionは`go/e2e/c-plugin/`へ配置し、独立したE2E ShellScriptは使用しません。E2E packageは`vp test`と`moon test`から除外し、Vite+ workspace task経由で収集します。

```text
src/e2e/
└── Dockerfile

go/e2e/c-plugin/
├── e2e_test.go
├── scenario_helpers_test.go
├── *_test.go
└── vite.config.ts
```

`src/e2e/`には`moon.pkg`を配置せず、E2EファイルにMoonBitのテストsuffixを使用しません。Go E2E packageのVite+ test taskはrepository CIにも収集されます。

runnerの契約は次のとおりです。

1. Go testの実行前に、Vite+ setup taskが軽量な`c-plugin-e2e-image` Just recipeを実行し、現在のrepository contextからcaller所有の`c-plugin-e2e:local` imageをビルドする。
2. image内で`moon install`を1回実行し、実際のnative c-plugin executableを1回だけビルドする。
3. Goシナリオは共通E2E helper関数を通してJSON、repository、filesystem fixtureを作成する。Testcontainersで必要なinfrastructure commandはhelper内だけで許可し、シナリオからShellScriptをdispatchしない。
4. Go packageはビルド済みのlocal imageとともに共通の`totto2727-org/e2e` libraryを呼び出し、libraryは末端コマンドのシナリオごとに個別の破棄可能なTestcontainers containerを実行する。
5. 共通libraryまたはコマンドテスト内でimageのビルドや削除を行わない。callerが所有するimageはsuite完了後も維持される。

すべてのテストcontainerは、分離された一時`HOME`、working directory、cache root、target directoryを使用します。したがって、global modeのcaseがhost userへ影響することはありません。

旧GitHub E2E計画は`totto2727-org/monorepo`をfixture sourceとしていましたが、現8件のlocal caseはこの経路を検証していません。GitHub機能を導入するときに旧製品削除後も有効なfixture repository/commitを選定・検証し、少なくとも将来のGitHub add/updateで実bit経路を実行してください。

各末端コマンドのGoシナリオは少なくとも1つの正常系を扱い、そのコマンドに関連するfilesystem state、lock JSON、command output、exit statusをassertします。syncシナリオでは、生成済みのロックを外部から編集し、古くなった所有linkが削除されることと、置換された管理外pathが維持されることを検証します。updateシナリオでは、同じリポジトリを異なるcommitに固定した2つのプロジェクトロックを使用し、一方のロックをupdateしても他方のロックのcacheとlinkが変化しないことを検証します。対話状態は主に単体テストで検証し、Docker実行を決定論的にするため、E2Eでは明示的な非対話selection optionを使用します。

## 旧設計の実装milestone


以下の旧milestone IDは設計履歴であり、完了状態を示しません。
v1共存を復活させる指示でもありません。
この旧milestone見出し以下の全小節は元の計画文脈を保存するもので、現在の実行指示ではありません。

c-plugin v2は一度に全面的に書き換えず、独立してレビュー可能なマイルストーンの連続として実装します。各マイルストーンでは、利用可能な1つの垂直スライスを追加し、同じ変更内にテストを含め、次のマイルストーンへ進む前に報告して停止します。

旧Milestone 0は設計契約の記録であり、製品実装の完了ではありません。Milestone 1から7では、次の安定した原子的単位IDを使用します。同じwave内のcomma区切りだけを並行化候補とし、arrowは厳密な順序制約とします。原子的単位`M1`はMilestone 3に属し、Milestone 1のparent issueとは別です。

| マイルストーン                    | 原子的な単位                                                                                                                                                                                                                            | 依存関係と並行wave                                                                                        |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| 1. Bootstrap                      | `B0` v1共存identity/layout契約、`B1` native dependency compatibilityと正確な`mizchi/bit` APIを証明してからCLI skeleton・help・versionを作成、`B2` `c-plugin-v2` Nix packageを追加                                                       | `B0 -> B1 -> B2`                                                                                          |
| 2. 状態基盤                       | `F0` runtime path、`F1` domain/lock model、`F2` lock codec、`F3` ownership codec、`F4` atomic store、`F5` cache scope、`F6` discovery、`F7` runtime composition、`C-init` init、`E0` Docker/init E2E                                    | `F0,F1 -> F2,F3,F5,F6 -> F4,F7 -> C-init -> E0`                                                           |
| 3. ローカルライフサイクル         | `M0` marketplace解析、`M1` local/skill解決、`R1-P` desired-link planning、`R1-FS` ownership-safe filesystem reconciliation、`C-sync`、`A1` `persist_and_sync`、`C-sync-r`、`C-add-local`、`C-remove`、`C-target-add`、`C-target-remove` | `M0,M1 -> R1-P -> R1-FS -> C-sync -> A1,C-sync-r -> C-add-local,C-target-add -> C-remove,C-target-remove` |
| 4. GitHubライフサイクル           | `G0` freeze済みbit contract/adapterの前提条件、`G1` clone/checkout/HEAD、`G2` fetch/default branch、`G-add`、`G-update`、`G-update-r`、`G-cleanup`                                                                                      | `G0 -> G1 -> G2 -> G-add,G-cleanup -> G-update -> G-update-r`                                             |
| 5. 対話入力                       | `I1` selection state/TUI adapter、`I2` TTY方針、`I-add-kind`、`I-add-skill`、`I-remove`、`I-target-remove`                                                                                                                              | `I1 -> I2 -> I-add-kind,I-add-skill,I-remove,I-target-remove`                                             |
| 6. マーケットプレイス作者向け機能 | `D0` 共通read model、`D1` format変換、`D2` 決定論的write、`C-dev-sync`                                                                                                                                                                  | `D0 -> D1 -> D2 -> C-dev-sync`                                                                            |
| 7. 最終等価性とcutover            | `P1` 完全parity matrix、`P2` 文書/parity audit、`P3` cutover                                                                                                                                                                            | `P1 -> P2 -> 明示的なcutover承認 -> P3`                                                                   |

### 単位ごとの検証契約

各原子的な単位では、動作とテストを同じ変更に含めます。`B0`では文書化したv1/v2のpathとidentity、v1が未変更であること、両versionが同じlock scopeを共有しないことを検証します。`B1`では固定した全dependencyと正確な`mizchi/bit` APIを使用するnative buildを証明してから、対象を絞ったcheck・format・parser test・native buildを実行し、実際の`--help`/`--version`とAdmiral名`c-plugin`を確認します。`B2`では`c-plugin-v2` Nix packageをbuild/evaluateし、そのexecutableが動作してv1 packageが未変更であることを検証します。`F0`と`F1`ではconstructor・normalization・拒否・仮home、`F2`ではcanonical round trip・JSON path・strict failure・未対応versionのbyte維持・最上位dispatch、`F3`では厳格なownership-state round trip、`F4`ではexclusive create・temporary-sibling rename・永続化前後の失敗、`F5`ではSHA-256から導出するCacheScopeの正確なscope key・検証済みmetadataの生成とround trip・canonicalization・lock移動・2ロックcache分離をテストします。metadata不一致の拒否は、永続化metadataを利用する将来のcache storage adapter testでその利用境界に対して検証します。`F6`ではnearest project・exact global・ignore/recursive descendant・home境界・`-g`/`-r`、`F7`では全runtime boundaryの注入と実ユーザーpathの非使用をテストします。`C-init`ではproject/global正常系・既存fileのbyte維持・不正scope・繰り返しをテストし、`E0`ではimage/executableを1回だけbuildして、分離したproject/global initのstatus・output・lock JSON・host stateをassertします。

`M0`と`M1`ではClaude/Cursor/Codexとlocal fixtureを使い、明示的なkind/skill選択・重複ID・ordering・不正manifest・正規化pathをテストします。`R1-P`ではfilesystemを変更せず、enabled skill filtering、不変なdesired ownership、canonical repository precedence、provenance、unavailable repository、正規化link pathを網羅します。`R1-FS`では不足・古い・管理外・置換済み・壊れたlink、欠落/破損ownership state、削除target、一部失敗、冪等性、ロック間分離を網羅します。`C-sync`と`C-sync-r`ではunit flowとclean-container E2Eを追加し、外部編集したlockとignore対象のrecursive descendantも検証します。`A1`では成功した全mutationが永続化済みcandidateと同じ値をsyncし、cancel/no-opはwriteもsyncも行わず、write後のsync失敗から復旧できることを証明します。`C-add-local`、`C-remove`、`C-target-add`、`C-target-remove`は、それぞれunitと独立したclean-container E2Eで、該当するstatus/output、canonical lock、link/state、繰り返しまたは選択、cleanup、管理外path維持をassertします。

`G0`では`B1`で証明済みの正確なAPIを使用し、bit adapter contractをfreezeして、その型付きboundaryと注入したfailure behaviorをテストします。Dependency/API compatibilityの証明は繰り返しません。`G1`と`G2`ではscoped serialization、pin、fetch/default branch、一部失敗、2ロック分離をテストします。`G-add`では実際のbit-backed `totto2727-org/monorepo` unit/E2Eでlock・cache・link・output・statusをassertします。`G-update`と`G-update-r`ではpin更新、local source非fetch、recursive/failure分離、永続化済み状態のsync、兄弟lock/cache/link不変のunit/E2Eを追加します。`G-cleanup`ではlink調整後に所有lockの最終参照だけがcacheを削除することを証明します。

`I1`と`I2`ではchoose・preselection・cancel・empty selection・TTY検出・必須非対話optionをテストします。`I-add-kind`、`I-add-skill`、`I-remove`、`I-target-remove`ではprompt-to-domain mappingを個別にテストして実TTYを手動観察し、非TTY regressionで暗黙defaultと全選択を禁止します。`D0`と`D1`では全format、正規化済みCodex local source、installation policy、不正input、変換、orderingをfixture testします。`D2`では一時root上で所有outputの置換と無関係fileの維持をテストします。`C-dev-sync`ではsource kindごとのunitとclean-container E2Eで、生成/copy/維持file・output・statusをassertします。`P1`では全対象check/format/build/unit testと分離Docker scope横断matrixを実行し、`P2`ではexecutableの証拠に対して全受け入れ条件を監査して両文書を同時更新します。明示承認後だけ`P3`でrollbackを維持しながらexecutable/Nix entryを切り替え、cutover surfaceで`P1`を再実行し、v1/v2が同じlock scopeを共有しなかったことを証明します。Lock migrationは含めません。

### Linearとnative stackのcontrol plane

- 1つのumbrella Linear issueとMilestone 1から7の7つのparentを使用し、各milestone parentを前のmilestoneによって順次`blockedBy`する。
- Activeな原子的単位ごとにchildを厳密に1つ作る。将来のatomic issueを先に作らず、前のmilestoneの承認後、対象milestone開始直前にjust-in-timeで展開する。
- 1 atomic unitを1 commit、1 native stack layer、1 PRに対応させる。Branch名は`codex/cpv2-m<N>-<unit>-<slug>`とし、base-to-tip順を維持する。
- Native GitHub stacked PR submissionをhard gateとする。Submission直前にversion `2026-03-10`のREST APIとinstalled `gh` extension listを再確認する。現在観測済みの`404`はsubmissionをblockする。
- 通常のdependent PR chainへ暗黙にfallbackしたり、それをnative stackと呼んだりしない。`gh-stack`を暗黙にinstallしない。対応後は下記の公式`gh stack` commandだけを使用する。
- Team modeは、上表のcomma区切りの並行waveで共有contractをfreezeした後だけ、workerごとに分離worktreeを使用して実行できる。Arrowは順次のまま維持する。

### マイルストーンの規則

- 現在のマイルストーンが未完了またはユーザーレビュー待ちの間は、後続マイルストーンを開始しない。
- 各マイルストーンの完了後に停止し、次のマイルストーンを実装する前に明示的な承認を待つ。
- 各マイルストーンを1つの一貫したレビュー可能な変更単位に保つ。将来のコマンドstub、未使用のabstraction、推測的なcompatibility code、無関係なcleanupを前のマイルストーンへ持ち込まない。
- 保護対象のproduction behaviorと同じ変更内で単体テストを追加する。テストを最終マイルストーンへ先送りしない。
- Milestone 2でDocker harnessを追加し、末端コマンドが最初に利用可能になった時点でE2Eファイルを追加する。Milestone 7では、すべてのE2Eテストを一度に作成するのではなく、完成したmatrixを実行して監査する。
- 各マイルストーンで、それ以前に提供したすべてのマイルストーンをgreenに保つ。
- 依存関係またはupstream APIの非互換は、現在のマイルストーンだけをblockする。workaroundを選択する前に証拠を記録し、この設計を修正する。
- 中間コマンドが利用可能でも、Milestone 7を通過するまではc-plugin全体の機能等価性を主張しない。
- `P2`後に停止する。`P1`と`P2`はcutover承認を意味せず、明示的なユーザー承認後だけ`P3`を開始する。

### マイルストーンの完了ゲート

マイルストーンの対象範囲について、次のすべてを満たした場合だけ完了とします。

1. 文書化した動作を、将来向けplaceholderなしで実装している。
2. 変更したMoonBit packageが、対象を絞ったcheck、format、build、unit test commandを通過している。
3. その時点までに追加したすべての末端コマンドが、clean containerでE2E正常系を通過している。
4. マイルストーンで追加したユーザー向けcommand surfaceを通じて、実際のexecutableを操作している。
5. マイルストーン報告を作成し、完了した動作と先送りした動作を明確に分離している。

### マイルストーン報告形式

各マイルストーンの引き渡しでは次を報告します。

- マイルストーン番号と結果。
- 新たに利用可能になったユーザー向け動作。
- 追加または変更したファイルとarchitecture boundary。
- 実行した単体テスト、build、E2Eの正確なコマンドと結果。
- ビルド済みexecutableに対して行った手動CLI確認。
- 既知の制限と意図的に先送りしたコマンド。
- 発見した依存関係またはupstreamのrisk。
- 次のマイルストーンで提案する対象範囲。

報告では、マイルストーンの境界で作業を停止したことを明記します。先送りした動作を部分的に実装済みと表現したり、自動的に次のマイルストーンへ進んだりしません。

## 計画上のfull-parity受け入れ条件

- コマンド体系が`c-plugin skill`を公開スキル管理名前空間として維持し、文書化したすべての末端コマンドを生成済みhelpとversion outputとともに公開する。
- Project、recursive、`-g`の各scopeが文書どおりに解決される。
- Global lockは`~/c-plugin-lock.json`であり、global linkは`~/.agents/skills`以下のままである。
- 明示的な文字列境界を除き、内部のpath valueに`Path`を使用している。
- リポジトリcacheは、正規化済みの絶対所有ロックパスから導出した完全なSHA-256キーで分離し、スコープmetadataによって衝突やロック間の暗黙の再利用を防止する。
- Git subprocessを一切起動せず、clone、fetch、checkout、HEAD解決に`mizchi/bit`ライブラリを使用している。
- Lock JSONが厳格でLens-backedかつcanonicalであり、`FromJson`と`ToJson`を通じてround tripする。
- 未対応のlock versionは変更を行わず失敗し、自動migrationとmigrationコマンドは現時点の実装対象に含めない。
- データを持つEnumが最上位の`type`フィールドで一度だけdispatchする。
- 既存directoryと管理対象outputを冪等に扱う。明示的なadd forceがcontainment確認済みの完全一致する通常ファイルまたはシンボリックリンクを置換する場合を除き管理外pathを保存し、実directory、特殊path、neighbor、managed root外のpathを上書きまたは削除しない。
- Machine-localな所有stateにより、外部からのロック変更後に古くなったc-plugin linkを`sync`で削除でき、置換済みまたは未所有のpathは削除しない。
- 既存ロックの変更が成功した場合、終了前に永続化した値と完全に同じ値を使用して必ず`sync`を実行する。
- 復元したすべての対話selectionが実TTYで動作し、対応する非対話optionがすべて決定論的に動作する。
- すべての状態を一時directory以下へ分離した単体テストが通過する。
- Docker E2E imageを1回だけビルドし、各末端テストを破棄可能なcontainerで実行し、すべての正常系が通過する。

## 一次資料

- MoonBit toolchainと`moon install`: https://docs.moonbitlang.com/en/latest/toolchain/moon/commands.html
- `moonbitlang/x/path.Path` public API: https://github.com/moonbitlang/x/blob/main/path/pkg.generated.mbti
- `totto2727/x@0.3.0/path`の検証済みpath値: https://mooncakes.io/docs/totto2727/x@0.3.0/path
- Admiral: https://github.com/totto2727/admiral
- mizchi/tui: https://github.com/mizchi/tui.mbt
- mizchi/bit: https://github.com/bit-vcs/bit
- GitHub REST repository path parameter: https://docs.github.com/en/rest/repos/contents
- NIST Secure Hash Standard（FIPS 180-4）: https://csrc.nist.gov/pubs/fips/180-4/upd1/final
- MoonBit async filesystem API: https://github.com/moonbitlang/async/blob/main/src/fs/pkg.generated.mbti
- Lens: https://github.com/totto2727-org/monorepo/tree/f0523b8e9232afa6a47b83cb62df607f2a83d6de/mbt/package/lens
- target-file-discovery: https://github.com/totto2727-org/monorepo/tree/f0523b8e9232afa6a47b83cb62df607f2a83d6de/mbt/package/target-file-discovery
- GitHub stacked pull request public preview発表: https://github.blog/changelog/2026-07-30-stacked-pull-requests-are-now-in-public-preview/
- GitHub stacked pull request概要: https://docs.github.com/en/pull-requests/get-started/about-stacked-prs
- 公式stacked PR CLI command: https://docs.github.com/en/pull-requests/reference/stacked-prs-cli-commands
- GitHub REST pull-request stacks API（`2026-03-10`）: https://docs.github.com/en/rest/pulls/stacks?apiVersion=2026-03-10
