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

これは`~/plugins/spaceguard`へプラグインを配置し、`~/.agents/plugins/marketplace.json`へ登録します。個人ルールの`~/.codex/AGENTS.md`は編集しません。

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

ChromeでURLを開く場合は、Codex Chrome Extensionの`tabs.new()`よりもこちらを優先します。`tabs.new()`は別デスクトップのChromeウィンドウへタブを作ることがあるためです。

```sh
spaceguard detect --json
spaceguard open-url --app "Google Chrome" "https://github.com/soichiro-nitta/spaceguard"
```

`open-url`、`assert`、`windows`は、現在の`CODEX_THREAD_ID`と最後の検出結果が一致している場合だけ動きます。別スレッドの検出結果が残っている場合は、その結果を使わず止まります。

複数のCodexウィンドウがあり、自動検出が曖昧な場合は推測せず止まります。ユーザーが「このスレッドはデスクトップ3」と明示できる場合は、手動で固定できます。

```sh
spaceguard bind --desktop 3
```

## Codexに入れておくルール例

`spaceguard setup-codex --with-agents-rule`を使うと、以下のような管理ブロックを`~/.codex/AGENTS.md`へ追加できます。

```md
Before using Chrome, Computer Use, or macOS desktop automation, use the SpaceGuard plugin workflow.

If the plugin is unavailable, run `spaceguard detect --json` and only operate in the detected `space.desktopName` when `confidence` is `high` or `cached-high`.

When opening a new Chrome URL, do not use the Codex Chrome Extension `tabs.new()` as the first step because it may create a tab in a Chrome window from another macOS Space. Use `spaceguard open-url --app "Google Chrome" <url>` first, then operate the tab after confirming it is in the detected Desktop.

If multiple Codex windows are open and SpaceGuard cannot infer the current thread's window, stop. If the user explicitly identifies the correct Desktop, run `spaceguard bind --desktop <n>` before continuing.
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
