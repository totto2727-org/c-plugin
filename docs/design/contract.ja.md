# 設計契約

この契約は、c-pluginを変更する開発者向けです。
ユーザー向けのコマンド仕様は[CLIリファレンス](../cli.md)に記載します。
この文書は[英語版](contract.md)の翻訳であり、同じ範囲と要件を扱います。

## 対象範囲

c-pluginは、Agent Plugins 1.0パッケージ形式のスキルだけをローカルからインストールするツールです。
Haskell、Cabal、Iris、固定したNix環境を使用します。
マーケットプレイス、ベンダー固有パッケージ、Gitリモート、MCPサーバー、hook、対話選択は管理しません。
これらの対象外機能のために、将来用のコマンドplaceholderを追加しません。

## 入力境界

CLI文字列、JSON、filesystem入力を解析した後は、検証済みのパスと識別子を使用します。
ローカルsourceと追加targetは、所有するロックのrootを基準に解決します。
親ディレクトリへの移動と、物理的なcontainmentからの逸脱を拒否します。
出力rootとその祖先はロックroot内の実ディレクトリでなければならず、symlinkによる転送を認めません。

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

## 状態

望ましい状態のロックは`c-plugin-lock.json`です。

```json
{
  "version": "3",
  "targets": [],
  "plugins": [
    {"source": "./demo", "name": "demo", "skills": ["alpha"]}
  ]
}
```

厳密な文字列version `"3"`と、すべての必須fieldを要求します。
未対応versionは、変換や変更を行わず拒否します。
source、plugin identity、選択skill、targetの重複を拒否します。
正規化した相対パスと決定的な順序でencodeします。
projectとglobalのロックを分離します。

machine-localな所有stateは`.agents/c-plugin-state.json`で、versionは`"1"`です。
これは共有可能な望ましい状態の設定ではありません。
各entryは、絶対link path、managed root、正確なliteral symlink target、resolved target、source/plugin/skill identityを記録します。
literal targetはresolved pathと分離し、変更せずround-tripしなければなりません。

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

## 安全規則

- filesystem kind、literal target、resolved target、containmentが記録と一致する場合だけ、所有linkを削除または置換する。
- 置換済みpathは保存し、所有権の喪失を報告する。
- 所有stateの欠落や破損は、既存pathのcleanupやadoptionを決して許可しない。
- 未記録の既存linkが望ましいtargetを指すという理由だけでadoptionしない。
- 明示的add forceは、containment内の完全一致する通常ファイルまたはsymlinkの衝突だけを置換できる。
- 実ディレクトリ、特殊ファイル、隣接path、managed root外のpathを削除しない。
- 削除されたtarget rootの古い所有entryを、安全なcleanupに使用できるよう保持する。
- plugin sourceが利用できないときは、解決失敗を理由にlinkを削除せず保存する。
- 再帰処理でもロックごとの所有権を分離し、探索時にsymlinkディレクトリを辿らない。

これらの確認は偶発的なscope逸脱を減らします。
同時にfilesystemを書き換える攻撃者に対するsandboxではありません。

## 実装境界

| ファイル/module | 責務 |
| --- | --- |
| `app/Main.hs` | Irisコマンドparserとprocess entrypoint |
| `CPlugin.Types` | 検証済みpath、identity、lock、ownership値 |
| `CPlugin.Codec` | 厳格なcodecとatomicなstate永続化 |
| `CPlugin.Paths` | 実行scope、探索、物理的containment確認 |
| `CPlugin.Plugin` | 標準manifestとskillの探索・検証 |
| `CPlugin.Reconcile` | 望ましいlink、所有権に基づく安全なmutation、checkpoint |
| `CPlugin.Commands` | Init、add、remove、sync、target workflow |

GHC 9.4.8とIris 0.1を公開された依存関係のbounds内で使用します。
依存関係のprobeを製品テストの代わりにしません。

## 検証

native testは、分離した一時rootを使って実際の製品境界を検証します。
Go/Testcontainers scenarioは、callerがbuildしたimageを使い、登録caseごとに独立した破棄可能containerを実行します。
sourceに対応するscenario文書を実際のGoディレクトリに対して検証します。
native test、実Docker E2E、Nix package buildの結果を分けて報告します。
文書例は期待する動作を示すものであり、テストが通過した証拠ではありません。

## 一次資料

- [Agent Plugins 1.0 specification](https://agent-plugins.org/specification)
- [Plugin manifest schema](https://agent-plugins.org/schemas/1.0.0/plugin.schema.json)
- [Agent Skills specification](https://agentskills.io/specification)
- [Iris package](https://hackage.haskell.org/package/iris)
