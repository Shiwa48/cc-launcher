# Claude Code Launcher（cc-launcher）

タスクバーから、好きなフォルダで Claude Code を開くための常駐ツール。
Windows Terminal の新しいウィンドウで `claude` を起動する（`claude` を終了してもシェルは残る）。

> 個人用に作ったツールです。動作の保証やサポートはなく、更新も気まぐれです。

## 動作環境

- Windows 11
- PowerShell 7.5 以上（WPF の Fluent テーマを使うため .NET 9 以降が必要）
- Windows Terminal
- [Claude Code](https://docs.claude.com/en/docs/claude-code)（`claude` コマンドが PATH にあること）

## インストール

好きな場所に置いて（clone して）、そのフォルダで実行する。インストール後にフォルダを移したときは、もう一度実行すればショートカットが付け直される。

```powershell
pwsh -File .\install.ps1
```

- スタートメニューに「Claude Code Launcher」、スタートアップに常駐用、エクスプローラーの「送る」に「Claude Code」のショートカットを置く。
- **レジストリは書き換えない**。置くのはショートカット3つと設定ファイルだけで、`uninstall.ps1` で全部消える。
- **タスクバーへのピン留め**：スタートメニューで「Claude Code Launcher」を右クリック →「タスクバーにピン留めする」。
  ピン留めしたアイコンを右クリックすると、お気に入りと最近のフォルダが並ぶ（ジャンプリスト）。
- 一部だけ登録したくないとき：`-NoStartup`（自動起動しない）、`-NoSendTo`（「送る」に追加しない）、`-NoStart`（今は常駐させない）。

## 使い方

開き方：**`Ctrl+Alt+C`**（どこからでも）／トレイアイコンの左クリック／ピン留めしたアイコンのクリック

| 操作 | キー |
|---|---|
| 絞り込み | そのまま文字を打つ（フォルダ名・パスで検索。`C:\...` のようにパスを打つか貼り付けると、そのフォルダが候補になる） |
| 選択 | ↑ ↓（PageUp / PageDown） |
| 新しいセッションで開く | Enter（またはダブルクリック） |
| 直前の会話の続き（`--continue`） | Ctrl+Enter |
| セッションを選んで再開（`--resume`） | Shift+Enter |
| お気に入りに追加・解除 | Ctrl+D |
| お気に入りの並べ替え | Alt+↑ ↓ |
| 履歴から削除 | Del（検索欄が空のとき） |
| フォルダ選択ダイアログ | Ctrl+O |
| 閉じる | Esc（入力中なら、1回目はクリア） |

- エクスプローラーでパスをコピーしてからパネルを開くと、そのフォルダが「クリップボード」として一番上に出る。
- 行を右クリックすると、起動方法の選択、お気に入り、エクスプローラーで開く、履歴から削除ができる。
- トレイアイコンの右クリック：お気に入りからすぐ起動、設定ファイルを開く、ログオン時に起動の切り替え、終了。
- エクスプローラーでフォルダ（またはファイル）を右クリック →「その他のオプションを確認」→「送る」→「Claude Code」。そのフォルダが入った状態でパネルが開くので、Enter／Ctrl+Enter／Shift+Enter で起動方法を選ぶ。

## 設定

`%APPDATA%\cc-launcher\config.json`（トレイメニューの「設定ファイルを開く」から開ける）

| キー | 意味 | 既定値 |
|---|---|---|
| `hotkey` | パネルを開くキー（例 `Ctrl+Alt+C`, `Win+Shift+Space`）。変更後はトレイから終了して再度起動する | `Ctrl+Alt+C` |
| `recentMax` | 履歴に残す件数 | 20 |
| `favorites` | お気に入り（`path` と表示名 `name`。`name` は書き換えてよい） | |
| `recent` | 最近使ったフォルダ（自動） | |

## コマンドライン

```powershell
cc-launcher.ps1 -Show                         # パネルを出す（常駐していなければ常駐も始める）
cc-launcher.ps1 -Show -Path C:\work           # そのフォルダを入れた状態でパネルを出す
cc-launcher.ps1 -Resident                     # 常駐だけ始める
cc-launcher.ps1 -Open C:\work -Mode continue  # そのフォルダで直接起動（new / continue / resume）
cc-launcher.ps1 -Quit                         # 常駐を終了する
```

## アンインストール

```powershell
pwsh -File .\uninstall.ps1                # お気に入りと履歴は残す
pwsh -File .\uninstall.ps1 -RemoveConfig  # すべて消す
```

## 仕組み

- PowerShell 7 + WPF（Fluent テーマ。ライト/ダークは OS に合わせる）+ WinForms の NotifyIcon。ビルドは不要。
- `lib\Native.cs`（ホットキー、別プロセスからの合図、AppUserModelID、角丸）は初回にコンパイルし、`%LOCALAPPDATA%\cc-launcher` にキャッシュする。
- 黒い窓を出さないために `conhost.exe --headless pwsh ...` で起動している。
- 二重に起動しない：2つ目の起動は常駐中のプロセスに「パネルを出して」と合図して終わる。
- 作るもの：スタートメニュー・スタートアップ・SendTo のショートカット、`%APPDATA%\cc-launcher`（設定）、`%LOCALAPPDATA%\cc-launcher`（ログとキャッシュ）。レジストリは読む（テーマの判定）だけ。
- ログ：`%LOCALAPPDATA%\cc-launcher\cc-launcher.log`
- アイコンを作り直すとき：`pwsh -File assets\make-icons.ps1`
