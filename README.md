# SpaceGuard

SpaceGuardは、CodexがmacOSの別デスクトップにいるChromeやアプリをうっかり触らないようにするためのCLIです。

たとえば、デスクトップ1は別プロジェクト、デスクトップ3は今のSpaceGuard作業、みたいに分けているとします。このときCodexに「Chromeで開いて」と頼むと、何もしないと別デスクトップのChromeにタブを作ってしまうことがあります。

SpaceGuardは「このCodexスレッドはどのデスクトップにいるのか」を見て、ChromeやComputer Useの操作をそのデスクトップ内に閉じ込めるための小さなガードです。

できることは、ざっくり以下です。

- Codexの現在のスレッドがあるデスクトップを検出する
- そのデスクトップ内にあるChrome、Finder、エディタなどのウィンドウを一覧する
- ChromeのURLを、対象デスクトップ内のChromeウィンドウへ開く
- 対象デスクトップに目的のアプリがない場合は、別デスクトップのウィンドウを勝手に触らず止める
- 複数のCodexウィンドウがあり判定が曖昧な場合は、推測せず止める

内部的には、Codexの`CODEX_THREAD_ID`、macOSのAccessibility、`com.apple.spaces`のSpaces情報、CoreGraphicsのウィンドウ情報を突き合わせています。macOSのSpaces情報には非公開/非安定なデータを使っているため、安定した公式APIとしてではなく、ローカル運用を安全にするための実用ツールとして扱ってください。

## インストール

### ワンラインインストール

通常はこちらを使います。

```sh
curl -fsSL https://raw.githubusercontent.com/soichiro-nitta/spaceguard/refs/heads/main/install.sh | zsh
```

`~/.local/bin/spaceguard`へCLIがインストールされます。

### cloneしてインストール

```sh
git clone https://github.com/soichiro-nitta/spaceguard.git
cd spaceguard
./install.sh
```

### Homebrew

Homebrew用のtapもあります。

```sh
brew tap soichiro-nitta/tap
brew install --HEAD spaceguard
```

tapリポジトリは[`soichiro-nitta/homebrew-tap`](https://github.com/soichiro-nitta/homebrew-tap)です。このリポジトリ内の`Formula/spaceguard.rb`は、式の元ファイルとして残しています。

## 初回実行

SpaceGuardはCodexウィンドウの位置をAccessibility経由で読み取ります。そのため、初回はmacOSのアクセシビリティ権限が必要です。

1. Codex内で`spaceguard detect --json`を実行します。
2. macOSが権限を求めたら、`システム設定 > プライバシーとセキュリティ > アクセシビリティ`で対象アプリを許可します。
3. もう一度`spaceguard detect --json`を実行します。

## 推奨macOS設定

SpaceGuardは、macOSのSpacesの挙動が安定しているほど使いやすくなります。

`システム設定 > デスクトップとDock > Mission Control`で、以下をおすすめします。

- `最新の使用状況に基づいて操作スペースを自動的に並べ替える`をオフ
- `アプリケーションの切り替えで、アプリケーションのウィンドウが開いている操作スペースに移動`をオフ
- 複数ディスプレイを使う場合は、`ディスプレイごとに個別の操作スペース`をオン

関連ポスト:

- [アプリ切り替え時に別Spaceへ飛ばされないための設定](https://x.com/soichiro_nitta/status/2053734918803587308)
- [Spaceの順番を勝手に入れ替えないための設定](https://x.com/soichiro_nitta/status/2053744066744275330)
- [複数ディスプレイ利用時のSpaces設定](https://x.com/soichiro_nitta/status/2054402153285025979)

## Codex向けセットアップ

SpaceGuardはCodexプラグインとしても使えます。ただし、プラグインだけではCLI本体は入りません。先にCLIをインストールしてください。

Codexへプラグイン登録するには、以下を実行します。

```sh
spaceguard setup-codex
```

これは`~/plugins/spaceguard`へプラグインを配置し、`~/.agents/plugins/marketplace.json`へ登録します。SpaceGuardの横断スキル`spaceguard-safe-desktop-operation`も、このプラグイン内の`skills/`から配布されます。個人ルールの`~/.codex/AGENTS.md`は編集しません。

SpaceGuardに関するChrome、Computer Use、macOS Desktop/Space判定の手順は、このrepoのCLIと同梱スキルを正本にします。特定プロジェクトのops repositoryへSpaceGuardの詳細手順を複製せず、プロジェクト側には対象アプリ、ログインロール、確認対象URLのようなドメイン固有情報だけを置きます。

変更予定だけ確認したい場合:

```sh
spaceguard setup-codex --dry-run
```

Codexの個人ルールにもSpaceGuard用の管理ブロックを追加したい場合:

```sh
spaceguard setup-codex --with-agents-rule
```

このモードでは、各ステップで確認を取り、`~/.codex/AGENTS.md`を書き換える前にバックアップを作ります。

確認なしで実行する場合:

```sh
spaceguard setup-codex --with-agents-rule --yes
```

## 使い方

### コマンド早見表

| コマンド | 使う場面 | 役割 |
| --- | --- | --- |
| `detect --json` | 最初に必ず実行 | このCodexスレッドが属するデスクトップを検出する |
| `windows --json` | 対象デスクトップの状態確認 | 検出済みデスクトップ内のウィンドウを一覧する |
| `assert --app "<name>"` | 対象アプリを触る前 | 検出済みデスクトップ内に対象アプリのウィンドウがあるか確認する |
| `open-url --app "Google Chrome" "<url>"` | ChromeでURLを開く時 | 検出済みデスクトップ内のChromeにバックグラウンドタブを作る |
| `open-url --activate --app "Google Chrome" "<url>"` | 表示切り替えを許容して開く時 | 検出済みデスクトップ内のChromeを前面化し、新規タブをアクティブにする |
| `status` | 現在の保持状態を見る時 | スレッド別に保存された作業場所と検出状態を確認する |
| `clear` | 現在スレッドの保存状態を破棄したい時 | スレッド別の作業場所と検出キャッシュを消す |
| `clear --all-stale` | 古い保存状態を掃除したい時 | 最終使用から30日を超えたスレッド別保存を消す |

Chromeの新規URL確認では、まず`open-url`を使います。Codex Chrome Extensionの`browser.tabs.new()`は、ユーザーが別デスクトップのChromeを見ているとそちらに開く可能性があるため、最初のタブ作成には使わない方針です。

SpaceGuardは、対象デスクトップ内のChromeへURLを開くところまでを担当します。その後のタブ取得、タブ操作、タブグループ、クリーンアップはCodex Chrome ExtensionやChromeスキル側の責務として扱います。

`detect`、`windows`、`assert`、`open-url`は、同じスレッドの検出状態を読み書きします。これらは並列実行せず、`detect -> assert/windows/open-url`のように順番に実行してください。

現在のCodexスレッドがあるデスクトップを検出します。

```sh
spaceguard detect --json
```

例:

```json
{
  "ok": true,
  "confidence": "high",
  "threadName": "spaceguard作成",
  "space": {
    "desktopName": "デスクトップ3",
    "desktopIndex": 3,
    "internalSpaceId": 5
  }
}
```

検出済みデスクトップ内のウィンドウを一覧します。

```sh
spaceguard windows --json
```

対象デスクトップ内にChromeがあるか確認します。

```sh
spaceguard assert --app "Google Chrome"
```

対象デスクトップ内のChromeへURLを渡したい場合は、`open-url`を使えます。

```sh
spaceguard detect --json
spaceguard open-url --app "Google Chrome" "https://github.com/soichiro-nitta/spaceguard"
```

`open-url`は、デフォルトでは対象Chromeウィンドウへバックグラウンドタブを作ります。別デスクトップのChromeを前面化してSpace移動が起きることを避けるためです。タブをすぐアクティブにしたい場合だけ`--activate`を付けます。`--activate`を付けると、対象デスクトップ内のChromeウィンドウを前面化し、新しく作ったタブをアクティブにします。

ユーザーに見せるためのURLは、原則として`open-url`で開いた時点で止めます。続けてChromeタブを操作する必要がある場合は、ここから先をSpaceGuardの手順として扱わず、Codex Chrome ExtensionやChromeスキルのルールに従います。

SpaceGuardは、タブを開く前に対象Spaceを判定し、別SpaceのChromeを誤って選びにくくするための補助ツールです。タブ取得、タブグループ作成、既存タブの再利用、不要タブ整理、DOM確認、スクリーンショット、クリック操作はCodex Chrome Extension側の運用として扱います。

`open-url`、`assert`、`windows`は、現在の`CODEX_THREAD_ID`と最後の検出結果が一致している場合だけ動きます。別スレッドの検出結果が残っている場合は、その結果を使わず止まります。

検出結果はスレッドごとに`~/.spaceguard/detections/<thread-id>.json`へ保存されます。`~/.spaceguard/last-detection.json`はメニューバー表示や互換用の最新検出として残しますが、`assert`、`windows`、`open-url`は現在の`CODEX_THREAD_ID`に対応するスレッド別ファイルを優先します。そのため、別のCodexスレッドが同時に`detect`しても、現在スレッドの検出結果を上書きしにくくなっています。

`detect`がCodexウィンドウを直接特定できない場合でも、同じスレッドで保存済みのCodexウィンドウが同じデスクトップに残っているときは`thread-bound`としてその結果を再利用します。

スレッド別保存がない場合でも、同じスレッドで10分以内に`high`として検出済みで、同じCodexウィンドウが同じデスクトップに残っているときは`cached-high`としてその結果を再利用します。これは、ユーザーが別デスクトップを見ている間に`fallback-active-space`が現在表示中のデスクトップで検出結果を上書きしてしまう事故を避けるためです。キャッシュが古い、ウィンドウが移動済み、またはCodexウィンドウが見つからない場合は再利用しません。

`confidence=high`で検出できた場合、SpaceGuardは`~/.spaceguard/thread-spaces/<thread-id>.json`へ現在スレッドの作業場所を自動保存します。`open-url`、`assert`、`windows`はこのスレッド別保存を優先します。`fallback-active-space`は現在表示中のデスクトップへ寄る可能性があるため、永続保存しません。

複数のCodexウィンドウがあり、自動検出が曖昧な場合は推測せず止まります。対象スレッドのCodexウィンドウを表示してから、あらためて`detect`してください。

## 動作確認

ChromeやComputer Useを使う前に、対象デスクトップを検出できることを確認します。

```sh
spaceguard detect --json
spaceguard windows --json
spaceguard assert --app "Google Chrome"
```

ユーザーが別デスクトップを見ている状態でも、直前に同じスレッドで`high`検出できていれば、`detect`は`cached-high`で同じデスクトップを返すことを確認します。`cached-high`は10分以内のキャッシュだけを使い、対象Codexウィンドウが見つからない場合は使いません。

ChromeにURLを開く挙動は、まずバックグラウンドタブで確認します。

```sh
spaceguard open-url --app "Google Chrome" "https://github.com/soichiro-nitta/spaceguard"
```

前面化が必要な場合だけ`--activate`を付け、検出済みデスクトップ内のChromeウィンドウが前面化されることを確認します。

```sh
spaceguard open-url --activate --app "Google Chrome" "https://github.com/soichiro-nitta/spaceguard"
```

## Codexに入れておくルール例

`spaceguard setup-codex --with-agents-rule`を使うと、以下のような管理ブロックを`~/.codex/AGENTS.md`へ追加できます。

```md
Before using Chrome, Computer Use, or macOS desktop automation, use SpaceGuard only to identify the target macOS Desktop/Space for this Codex thread.

Run `spaceguard detect --json` and treat the detected `space.desktopName` as the target Space when `confidence` is `high`, `thread-bound`, `cached-high`, or `fallback-active-space`.

If multiple Codex windows are open and SpaceGuard cannot infer the current thread's window, stop and ask the user to bring the target Codex thread into view before continuing.

For Chrome tab creation, tab groups, claiming tabs, finalization, and browser operation details, follow the Codex Chrome Extension workflow and the user's global Chrome-operation rules. Do not use SpaceGuard rules as the source of truth for Chrome tab lifecycle.
```

## アンインストール

削除対象を確認します。

```sh
spaceguard uninstall --dry-run
```

SpaceGuardが管理しているファイルとCodex登録を削除します。

```sh
spaceguard uninstall
```

削除対象は以下です。

- `~/.local/bin/spaceguard`
- `~/.spaceguard/`
- `~/plugins/spaceguard`
- `~/.agents/plugins/marketplace.json`内の`spaceguard`エントリ
- `~/.codex/AGENTS.md`内のSpaceGuard管理ブロック

`~/.codex/AGENTS.md`全体は削除しません。SpaceGuardの管理マーカーで囲まれたブロックだけを表示し、確認してから削除します。

ルールブロックを残したい場合:

```sh
spaceguard uninstall --keep-agents-rule
```

## メニューバー補助

任意でメニューバー補助を起動できます。

```sh
spaceguard menubar
```

これは表示用です。エージェント運用の正本はCLIです。

## English Summary

SpaceGuard is a small macOS CLI for AI agents that need to keep Chrome, Computer Use, and desktop app automation inside the same macOS Desktop/Space as the current Codex thread.

It detects the Codex window for the current `CODEX_THREAD_ID`, maps that window to private macOS Spaces data in `com.apple.spaces`, and returns the target Desktop as text or JSON.

Typical workflow:

```sh
spaceguard detect --json
spaceguard assert --app "Google Chrome"
spaceguard open-url --app "Google Chrome" "https://github.com/soichiro-nitta/spaceguard"
```

Install:

```sh
curl -fsSL https://raw.githubusercontent.com/soichiro-nitta/spaceguard/refs/heads/main/install.sh | zsh
spaceguard setup-codex
```

This project intentionally uses private/undocumented macOS Spaces data. Treat it as a pragmatic local guardrail for agent workflows, not as a stable public macOS API.
