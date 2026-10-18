# 設計契約

この契約は、c-pluginを変更する開発者向けです。
ユーザー向けのコマンド仕様は[CLIリファレンス](../cli.md)に記載します。
この文書は[英語版](contract.md)の翻訳であり、同じ範囲と要件を扱います。

## 対象範囲

c-pluginは、Agent Plugins 1.0パッケージ形式のスキルと単体skillをローカルまたは固定commitのGitHub sourceからインストールするツールです。
Haskell、Cabal、Iris、固定したNix環境を使用します。
マーケットプレイス、ベンダー固有パッケージ、GitHub以外のリモート、MCPサーバー、hookは管理しません。
これらの対象外機能のために、将来用のコマンドplaceholderを追加しません。

## GitHub sourceと全体同期

pluginと単体skillのsourceは`github:org/repo/...path`または`local:./...path`の単一位置引数とし、prefixなしはエラーにします。
`--github`、`--local`、`--path`は廃止し、GitHubのbranch/tag/commitだけを任意の`--ref`で指定します。
local sourceの`--ref`、不足・矛盾したsource、複数source、traversalはエラーにし、推測・補完・別ディレクトリへのfallbackは行いません。
repositoryはowner/repoまたは固定GitHub HTTPS URLとして検証し、refとsubpathも専用型で検証します。
plugin/standaloneのロックrecordは任意のtyped originを持ち、repository、要求ref、subpath、解決commitを保存します。
ローカルrecordはoriginを省略し、既存のwire形式を維持します。
sourceはoriginから導出した`.agents/c-plugin/sources`内の固定snapshotと一致しなければなりません。
`CPlugin.Source.GitHub`はargvによるGit実行、専用staging、provenance、cache検証を担当します。
既存のcacheは削除・上書き・adoptせず、cleanupはそのfetchが作成したstagingだけに限定します。
Gitの対話認証、hook、submodule再帰、HTTPS以外のprotocolを無効にし、URL書き換えを拒否します。
checkoutとoffline検証はGit設定を隔離し、cacheの実ディレクトリ、remote、HEAD、provenance、tracked内容hash、symlink containmentを確認します。
Gitlibの公式APIと依存関係を検討した上で、限定的なsnapshot取得には標準`process`とGitを使用します。
判断の根拠は[Git transport](git-transport.md)に記載します。
Cabal版はPATH上のGitが必要で、Nix版はruntime依存を含みます。

トップレベル`sync`はpluginと単体skillの両方を固定sourceからofflineで同期します。
トップレベル`update`は両方のGitHub refを取得し、ロック単位で全candidateを検証してから保存・同期します。
変更のない成功updateもlinkを同期しますが、同一ロックは書き直しません。
取得失敗はそのロックを部分更新しません。
`-r`はGit cloneの再帰やref短縮ではなく、最近傍projectロックとその子孫ロックの探索です。
Admiral 0.6.2の原仕様に合わせ、最近傍ロック必須、own lock常時包含、directory-onlyの限定ignore規則、未除外hidden包含、symlink非追跡を維持します。
安全のため`.git`とsnapshot cacheは探索から除外します。
不足引数・option・subcommandは標準エラーと非ゼロ終了を維持し、そのcontextの完全helpを標準rendererで表示します。

## モジュールの責務

domain型の定義、純粋な検証、wire形式の変換は同じモジュールに置きます。
`CPlugin.Types`は型モジュールの再公開だけを行います。
filesystemやcommandモジュールにorphan JSON instanceを定義しません。

| モジュール | 所有する規則 |
| --- | --- |
| `CPlugin.Types.Source` | 必須source schemeと型付きsourceへの純粋な解析 |
| `CPlugin.Types.GitHub` | GitHub repository/ref/subpath/commit/originの型、検証、JSON変換 |
| `CPlugin.Types.Path` | 相対・絶対パスの型、検証、JSON変換 |
| `CPlugin.Types.Name` | 識別子の型、plugin/skill名の検証、JSON変換 |
| `CPlugin.Types.Plugin` | インストール対象pluginの型、選択の検証、JSON変換 |
| `CPlugin.Types.InstalledSkill` | 単独skill登録の型、検証、JSON変換 |
| `CPlugin.Types.Lock` | 望ましい状態の型、重複の検証、標準導出JSON、境界検証 |
| `CPlugin.Types.Ownership` | 関連する所有権記録の型、関係の検証、JSON変換 |
| `CPlugin.Types.PluginManifest` | 標準plugin manifestの型、デコード、検証 |
| `CPlugin.Types.Skill` | 探索済みskillの型、frontmatterのデコードと検証 |
| `CPlugin.Types.Sync` | 同期結果と通知の型 |
| `CPlugin.Types.Selection` | 選択要求、型付き選択結果、行入力の検証 |

Iris CLI解析と対話modeの判定は`hs/app/Main.hs`に置きます。
`CPlugin.Interaction`は型付き選択肢をterminal handleへ接続し、handlerはcandidateの構築前に型付き選択結果を受け取ります。
`CPlugin.StateStore`はファイルIO、canonical JSON出力、耐久性を持つatomic writeを担当します。
型固有のwire形式規則は定義しません。
探索は`CPlugin.Plugin`、filesystem containmentは`CPlugin.Paths`、同期は`CPlugin.Reconcile`に置きます。
`CPlugin.Commands`はcommand値を操作ごとのhandlerモジュールへ振り分けるだけです。
一覧の表示や関連するplugin/skill変更には、小さい共有helperを使用できます。
`CPlugin.Commands.Common`は共有のロック読み込み、candidate永続化、完了結果の報告を担当します。
`syncLoadedLock`は計画と同期sessionを組み合わせるだけです。
`CPlugin.Reconcile.Plan`はsourceと望ましいlinkの解決、`Session`は通知とdurable checkpoint、`Mutation`は名前付きlink操作、`Report`はユーザー向けの結果出力を担当します。
これらの処理を移動するときも、mutation/checkpointの順序と例外を捕捉する範囲を維持します。
native specは責務別のモジュールへ分け、共有の隔離fixtureは`CPlugin.TestSupport`に置きます。

## 入力境界

CLI文字列、JSON、filesystem入力を解析した後は、検証済みのパスと識別子を使用します。
ローカルsourceと追加targetは、所有するロックのrootを基準に解決します。
親ディレクトリへの移動と、物理的なcontainmentからの逸脱を拒否します。
出力rootとその祖先はロックroot内の実ディレクトリでなければならず、symlinkによる転送を認めません。

`plugin add`は単体の明示plugin root、`skill add`は単体の明示skillディレクトリを受け取ります。
親collectionを探索せず、入力種別を推測せず、rootのリストも受け付けません。
plugin root直下には`plugin.json`、単独skill root直下には`SKILL.md`を必須とします。
物理的な解決後もsourceを所有するロックroot内に維持します。
標準manifestにはskill一覧fieldがないため、plugin skillには固定の`skills/`直下だけを使用します。

ローカルに実装したAgent Plugins 1.0 manifest規則を適用します。

- plugin rootの`plugin.json`と、厳密に対応する`$schema`識別子を必須とする。
- 必須nameと許可されたmetadataの型を検証する。仕様が文字列型だけを要求する項目に、URL、email、SPDX、semantic versionの追加制約を課さない。
- 未知のmanifest最上位fieldは報告して無視する。
- objectではない`extensions`は、致命的でないfieldとして無視する。
- その他のmanifest違反は、skill探索の前に拒否する。
- 実行時にschemaを取得せず、ベンダー形式へfallbackしない。

skillは`skills/`の直下の子ディレクトリからだけ探索します。
各`SKILL.md`は、解決後のplugin root内にある通常ファイルへ解決されなければなりません。
ディレクトリ名とnameの一致を含め、Agent Skills形式に従ってfrontmatterを検証します。
無効なskillは報告してskipし、有効な兄弟skillを無効にしません。
明示的に選択したskillが利用できない場合は拒否します。
未対応component typeは、その内容を実行せず無視します。
この契約は完全なconformance認証を示すものではありません。

## 対話境界

[Iris 0.1.0.0](https://hackage.haskell.org/package/iris-0.1.0.0)は`cliEnvInteractiveMode`とglobal optionの`--no-input`を提供します。
[interactive module](https://hackage.haskell.org/package/iris-0.1.0.0/docs/Iris-Cli-Interactive.html)はterminal入力を判定しますが、選択widgetは提供しません。
このmodeと、prompt出力handleのterminal判定を組み合わせて使用します。
terminal adapterは[Brick](https://hackage.haskell.org/package/brick)を使い、stdinから入力してstderrに画面を表示します。
terminalの初期化と終了をbracketで管理し、確定、cancel、非同期割り込みのいずれでもterminal状態を復元します。

選択型と応答検証は`CPlugin.Types.Selection`に置きます。
入出力effectは`CPlugin.Interaction`、command policyは各handlerに置きます。
選択では型付きplugin/skillとtarget値を渡し、表示labelからidentityを再構築しません。
非terminalのtest入力には決定的な行入力adapterを維持します。CLIは引き続き非terminalでselectorの省略を拒否します。

対話modeでselectorが省略された場合、plugin設定、remove、target removeは選択を求めます。
単独skill addはpathだけで1項目を指定するため、選択promptを必要としません。
明示optionはpromptを省略します。
非対話modeでは明示selector、またはplugin設定の`--all`か`--none`を必須とし、pipe入力を消費したり暗黙に全選択したりしません。
Up/Downでfocusを移動し、Spaceで項目を切り替え、Enterで選択集合を確定します。
初期選択は空とし、`a`で全選択、`n`で選択を解除します。
1つのpluginが必要な場面で複数を選択した場合、candidateを書き込む前にpromptを繰り返します。
Esc、`q`、Ctrl-Dでは、設定を書き込まず同期もしません。
plugin設定で確定した空集合または`--none`は、plugin登録を維持したまま全skillを無効にします。
有効集合が同じ場合は意味的なno-opとし、異なる場合は前の集合を置き換えます。
removeの空選択はstateを変更しません。
非同期の割り込みを通常の選択errorとして捕捉しません。
removeではインストール済みskillを事前選択しません。

## 操作境界

`target`、`sync`、`update`はトップレベルに置きます。
plugin removeはplugin全体だけを選択肢にし、skill removeは有効なplugin skillと単独skillだけを選択肢にします。
最後のplugin skillを削除・無効化しても、plugin登録は維持します。
登録済みpluginのskill enable/disableは、利用できるskill名を有効集合へ追加・除去し、source identityの置き換えやGitHub refの取得は行いません。
登録済みsourceと完全なcandidateを検証してから、変更した有効集合を保存します。
cancelと意味的なno-opは保存も同期も行いません。

3種類のlistは選択scopeのロックだけを読み、source読込、cache検証、networkアクセス、state書込み、同期を行いません。
plugin一覧には無効化した登録も含め、skill一覧には有効なplugin skillと単独skillを含めます。
ロック欠落・破損はエラーとし、sourceが利用できない場合やlinkが欠落した場合も一覧表示の動作を変えません。

## 状態

望ましい状態のロックは`c-plugin-lock.json`です。

```json
{
  "targets": [],
  "plugins": {
    "demo": {"pluginName": "demo", "pluginSource": "plugins/demo", "enabledSkills": ["alpha"], "pluginOrigin": null}
  },
  "standaloneSkills": {}
}
```

recordと直和型には標準のGeneric導出JSON instanceを使い、primitiveな文字列/pathとmap keyにはnewtype導出instanceを使います。
field名、constructor tag、optional fieldのencodeをカスタマイズしません。
構造的なdecodeと検証は分離して各型のそばに置き、永続化とcacheの境界で検証付きdecoderを呼びます。
検証済みdomain値を再構築する前に、map keyとrecord内のidentityが一致することを確認します。
`standaloneSkills` mapには`installedSkillName`、`installedSkillSource`、`installedSkillOrigin`を持つrecordを保存します。
pluginと単独skillのoriginには`githubOriginRepository`、`githubOriginRef`、`githubOriginSubpath`、`githubOriginCommit`を使います。
cache pathを導出する前にrepository/ref/subpathと完全なcommit IDを検証し、recordのsourceと一致することを要求します。
local recordのoriginは`null`としてencodeします。
cache provenanceはrepositoryとcommitだけを保存し、異なるrefやsubpathで同じimmutable snapshotを共有できます。
単独skillのname/sourceの一意性を検証し、有効なplugin skillと同名の単独skillを拒否します。
旧wire形式への変換やfallback解析は提供しません。
source、plugin identity、選択skill、targetの重複を拒否します。
正規化した相対パスと決定的な順序でencodeします。
projectとglobalのロックを分離します。

machine-localな所有stateは`.agents/c-plugin-state.json`で、絶対link pathをkeyに持つ`ownershipEntries` mapを使います。
これは共有可能な望ましい状態の設定ではありません。
各entryは、絶対link path、managed root、正確なliteral symlink target、resolved target、source/plugin/skill identityを記録します。
literal targetはresolved pathと分離し、変更せずround-tripしなければなりません。
`entrySource`直和型は、`OwnershipSource`または`StandaloneSource`に対してAeson標準の`tag`と`contents`を使用します。
外部のAgent Plugins manifestとAgent Skills frontmatterは標準の形式と検証を維持します。

## 永続化と調整

`init`はロックを排他的に新規作成し、link同期を行いません。
既存ロックを変更するときは、次の順序を守ります。

1. 完全な候補状態を解決して検証する。
2. 同じディレクトリの一時ファイルとatomic renameを使ってロックを保存する。
3. 永続化した候補と完全に同じ状態を調整する。

拒否した候補と意味的なno-opは、ロックを書き換えず調整も起動しません。
通常の衝突と利用できないpluginは、部分的な成功として扱えます。
checkpoint、durability、検証の致命的な失敗では失敗を返し、ロックをrollbackしたと装いません。
後のsyncで永続化済みの望ましい状態を再試行できます。

各link mutationは次の順序で行います。

1. 物理的なcontainmentと、所有権または明示的forceの適格性を確認する。
2. 許可された完全一致のmutationだけを行う。
3. 新しいlinkを検証してから所有権を記録する。
4. 次のmutationの前に所有stateのcheckpointを保存する。

checkpoint失敗時は停止します。
atomicな置換でも、filesystem mutationと所有checkpointの間のcrash windowはなくなりません。
このwindowをまたぐ自動復旧や所有権adoptionを保証しません。

## 並列I/O

独立したリポジトリとファイルシステムのI/Oは、各走査で最大8ワーカーの順序付きプールを使って並列実行します。
ネストした走査も含め、実行中のGitプロセスとskill・lock・ignoreファイルの読み取りはプロセス全体で最大8件に制限します。
スロットを保持するのは末端のI/Oだけで、子処理の完了を待つ間は保持しません。
ワーカーの失敗や非同期割込みでは、依存ワーカーをキャンセルして終了を待ってから制御を戻します。

`update`はlockごとの同じリポジトリと要求refを1回だけ取得し、検証済みsnapshotをpluginと単体skillのsubpathで共有します。
オフラインの計画はlockごとの同じリポジトリと固定commitを1回だけ検証し、選択したsubpathは別々に検証します。
snapshotの破損はその選択全体を利用不可にしますが、無効なsubpathは正常な兄弟の選択を利用不可にしません。
同時にsnapshotを公開する処理は、リポジトリとcommitが一致し、完全な検証に成功した既存snapshotだけを再利用できます。
既存のcache entryは削除しません。

再帰コマンドは、互いに独立したlock rootの準備と反映を並列実行します。
祖先と子孫のrootは、読み取りも含めて探索順で実行します。
祖先の変更によって、子孫が選択するsourceやtargetが変化する場合があるためです。
同じlock内のリンク変更とownership checkpointは逐次実行します。
報告と衝突解決の順序は完了順ではなく、探索順と識別子の順序で固定します。
通常の失敗が発生しても、独立した別lockをcheckpointの途中で中断しません。
最初の失敗を報告する前に、ワーカー数の上限によって待機中の処理も含め、現在の独立した実行waveの全lockを完了させます。
失敗後に次の実行waveは開始しません。
lockをまたぐtransactionやrollbackは保証しません。

## 安全規則

- filesystem kind、literal target、resolved target、containmentが記録と一致する場合だけ、所有linkを削除または置換する。
- 置換済みpathは保存し、所有権の喪失を報告する。
- 所有stateの欠落や破損は、既存pathのcleanupやadoptionを決して許可しない。
- 未記録の既存linkが望ましいtargetを指すという理由だけでadoptionしない。
- 明示的add forceは、containment内の完全一致する通常ファイルまたはsymlinkの衝突だけを置換できる。
- add forceはmanaged target内の選択されたsource identityだけに限定し、他の登録はforceなしで通常のreconciliationを行う。
- 実ディレクトリ、特殊ファイル、隣接path、managed root外のpathを削除しない。
- 削除されたtarget rootの古い所有entryを、安全なcleanupに使用できるよう保持する。
- plugin sourceが利用できないときは、解決失敗を理由にlinkを削除せず保存する。
- 再帰処理でもロックごとの所有権を分離し、探索時にsymlinkディレクトリを辿らない。

これらの確認は偶発的なscope逸脱を減らします。
同時にfilesystemを書き換える攻撃者に対するsandboxではありません。

## Toolchain

GHC 9.4.8とIris 0.1を公開された依存関係のbounds内で使用します。
依存関係のprobeを製品テストの代わりにしません。

## 検証

native testは、分離した一時rootを使って実際の製品境界を検証します。
応答解析、型付き選択mapping、cancel、byteを保つno-op、明示rootの拒否、単独skill登録、plugin有効集合の置換、非対話modeの拒否を扱います。
HaskellのHspec/Caseyard suite内のpseudo-terminalで、実CLIの選択、再入力、cancel、割り込みを実行します。
prompt文字列だけでなく、terminal判定、exit status、stateの完全一致、最終link状態を検証します。
Hspec scenarioはCaseyardの公開APIを使い、callerがbuildしたimageとexampleごとの分離されたcontainer stateを使用します。
共有imageはsuiteの前に1回だけbuildし、個別exampleの中ではbuildしません。
並列実行はHspecの`parallel`と`--jobs=2`で制御します。
E2E host compilerは独立した`hs/e2e` Cabal projectで管理し、製品のGHC 9.4 buildは変更しません。
sourceに対応するscenario文書を実際のHaskell moduleに対して検証します。
通常のCabal buildとnative testを検証し、実Docker E2Eの結果を分けて報告します。
独立したNix package buildは任意であり、`just ci`の必須検証には含めません。
文書例は期待する動作を示すものであり、テストが通過した証拠ではありません。

## 一次資料

- [Agent Plugins 1.0 specification](https://agent-plugins.org/specification)
- [Plugin manifest schema](https://agent-plugins.org/schemas/1.0.0/plugin.schema.json)
- [Agent Skills specification](https://agentskills.io/specification)
- [Iris package](https://hackage.haskell.org/package/iris)
