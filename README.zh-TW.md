# Coralline Codex 安裝說明（繁體中文）

Coralline Codex 是專為 OpenAI Codex CLI 製作的 Coralline 移植版。它把 Codex
原生狀態列與隔離的 tmux 伴隨列結合：原生狀態列負責即時模型、推理強度、
context、使用限制與 token；Powerlevel10k 風格伴隨列顯示目錄、專案、詳細 Git
狀態、啟動模型／profile、經過時間、時鐘，以及可選的 Node、Python 環境。

本專案衍生自 [Nanako0129/coralline](https://github.com/Nanako0129/coralline)，
但不是上游 Claude Code 版本。授權與移植範圍請見 [NOTICE.md](NOTICE.md)。

## 系統需求

- Linux 或 macOS、Bash 4+
- Python 3.8+、Git 與已安裝的 Codex CLI
- tmux（顯示即時 Powerlevel10k 伴隨列；沒有 tmux 時仍可使用原生狀態列）
- Nerd Font；若無 Nerd Font，可切換 ASCII 模式

不需要 `jq`。

## 安裝

先 clone 並檢查原始碼，再執行本機安裝程式：

```bash
git clone https://github.com/waynehacking8/coralline-codex.git
cd coralline-codex
./install.sh
~/.local/bin/coralline-codex verify
```

若 `~/.local/bin` 不在 `PATH`，請把它加入 shell 設定。含空白的自訂路徑也受支援：

```bash
CODEX_HOME="$HOME/Library/Application Support/codex" \
CORALLINE_BIN_DIR="$HOME/bin with spaces" \
./install.sh
```

主要安裝方式是可先審查的本機 Git checkout；文件不要求使用 `curl | bash`。

## 啟動

```bash
coralline-codex
coralline-codex --model gpt-5.6 --profile work
coralline-codex --no-companion   # 只保留 Codex 原生狀態列
```

tmux 伴隨列使用獨立 server，不會讀取或修改你原本的 `~/.tmux.conf` 或既有
tmux session。非互動執行時會自動略過 tmux。

## 設定

互動式設定：

```bash
coralline-codex configure
```

非互動式設定：

```bash
coralline-codex configure --theme tokyo-night --style pill
coralline-codex configure --node on --python on --runtime-probe off
coralline-codex configure --ascii on
coralline-codex configure --show
```

`runtime-probe off`（預設）只讀取 `.nvmrc`、`.node-version`、
`.python-version`、virtualenv 或 conda 環境；`on` 才會額外執行
`node --version`／`python3 --version`。資料不存在時只隱藏該區段，不會填入
猜測值。

內建主題：`claude-coral`、`catppuccin-mocha`、`dracula`、
`gruvbox-dark`、`lunar-pink`、`mono`、`nord`、`reverie`、
`tokyo-night`。

## 更新

從 checkout 更新：

```bash
git pull --ff-only
./install.sh --update
coralline-codex verify
```

或使用安裝後的 Git 更新命令：

```bash
coralline-codex update
```

更新前，既有 runtime 與同名主題會備份到
`$CODEX_HOME/coralline-codex-backups/<時間戳>/`；使用者的伴隨列設定會保留。

## 解除安裝

```bash
coralline-codex uninstall
```

runtime、產生的主題與伴隨列設定會移到有時間戳的可復原備份；只有在命令
symlink 仍指向本安裝時才會移除它。Coralline Codex 不會修改
`$CODEX_HOME/config.toml`。

## 驗證

```bash
coralline-codex verify
./test/run.sh
```

renderer 在每次更新畫面時不會發出任何網路請求。Codex 目前沒有 Claude Code
式外部 `statusLine`／`subagentStatusLine` renderer，因此即時 Codex 專屬數據保留
在原生 footer；伴隨列不會捏造無法取得的 context、token 或 rate-limit 數值。
