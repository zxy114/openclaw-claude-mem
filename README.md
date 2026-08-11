# Persistent Memory for OpenClaw / OpenClaw 持久记忆系统

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-121011.svg?logo=gnu-bash&logoColor=white)](install.sh)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)](#前置条件--prerequisites)

**One command gives OpenClaw memory that survives across sessions.**

OpenClaw starts every conversation from zero. This installer wires in
[`claude-mem`](https://github.com/thedotmack/claude-mem) — which speaks the Anthropic
protocol and targets Claude Code — and ships an **Anthropic → OpenAI translation proxy**
so the summarization step can run on **any OpenAI-compatible model** (GLM, DeepSeek,
local models, …) instead of requiring a paid Anthropic API key just to write memories.

> 一条命令让 OpenClaw 拥有跨会话记忆。
> 内置 Anthropic → OpenAI 协议转换代理，记忆生成可跑在任意 OpenAI 兼容模型上，
> 不必为了写摘要而单独买 Anthropic API。

---

## 目录 / Table of Contents

- [功能介绍 / What This Does](#功能介绍--what-this-does)
- [架构图 / Architecture](#架构图--architecture)
- [前置条件 / Prerequisites](#前置条件--prerequisites)
- [快速安装 / Quick Install](#快速安装--quick-install)
- [手动安装 / Manual Install](#手动安装--manual-install)
- [配置参数 / Configuration](#配置参数--configuration)
- [工作原理 / How It Works](#工作原理--how-it-works)
- [故障排查 / Troubleshooting](#故障排查--troubleshooting)
- [兼容模型 / Compatible Models](#兼容模型--compatible-models)

---

## 功能介绍 / What This Does

**中文：**

OpenClaw 原生不具备跨会话记忆能力——每次新对话都从零开始，遗忘所有历史上下文。本技能包通过集成 `claude-mem`（一个专为 Claude Code 设计的持久记忆系统）解决这一问题。

核心功能：
- 每次会话结束后自动生成并存储记忆摘要（SQLite + ChromaDB 双存储）
- 新会话开始时自动注入历史上下文，让 AI 能接续上次的工作
- 通过 Anthropic→OpenAI 协议转换代理，支持使用 GLM（智谱）或任意 OpenAI 兼容的大模型替代昂贵的 Anthropic API 进行记忆生成

**English:**

OpenClaw has no cross-session memory by default — each new conversation starts from scratch with no context. This skill package integrates `claude-mem` (a persistent memory system designed for Claude Code) to fix that.

Key features:
- Automatically generates and stores memory summaries after each session (SQLite + ChromaDB dual storage)
- Automatically injects historical context at the start of new sessions
- Via an Anthropic→OpenAI protocol translation proxy, supports using GLM (Zhipu AI) or any OpenAI-compatible LLM instead of the expensive Anthropic API for memory generation

---

## 架构图 / Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         OpenClaw 会话                            │
│                      OpenClaw Session                           │
└────────────────────────────┬────────────────────────────────────┘
                             │ hooks.json 事件触发
                             │ hooks.json event trigger
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Hooks 层 / Hook Layer                       │
│  Setup / SessionStart / UserPromptSubmit / PostToolUse / Stop   │
└────────────────────────────┬────────────────────────────────────┘
                             │ bun-runner.js 调用 worker-service.cjs
                             │ bun-runner.js calls worker-service.cjs
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              claude-mem Worker (HTTP 127.0.0.1:37777)           │
│         记忆管理核心 / Memory management core                     │
└──────────────────┬──────────────────────┬───────────────────────┘
                   │                      │
                   ▼                      ▼
    ┌──────────────────────┐   ┌──────────────────────────────┐
    │      SQLite DB        │   │    ChromaDB (uvx, 本地)       │
    │  ~/.claude-mem/       │   │  ~/.claude-mem/chroma/       │
    │  claude-mem.db        │   │  向量语义检索                  │
    │  结构化记忆存储         │   │  Semantic vector search      │
    └──────────────────────┘   └──────────────────────────────┘

     记忆生成时 Worker 调用 LLM / Worker calls LLM for memory generation:

┌─────────────────────────────────────────────────────────────────┐
│             claude-glm wrapper (/usr/local/bin/claude-glm)      │
│     设置 ANTHROPIC_BASE_URL → 本地代理                            │
│     Sets ANTHROPIC_BASE_URL → local proxy                       │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│         anthropic-proxy.py (HTTP 127.0.0.1:9191)               │
│   Anthropic /v1/messages → OpenAI /chat/completions 协议转换    │
│   Protocol translation: Anthropic API → OpenAI-compatible API  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              GLM API / 任意 OpenAI 兼容 API                      │
│         GLM API / Any OpenAI-compatible API                     │
│     例如: open.bigmodel.cn/api/paas/v4 (glm-4-flash)           │
│     e.g.: open.bigmodel.cn/api/paas/v4 (glm-4-flash)          │
└─────────────────────────────────────────────────────────────────┘
```

---

## 前置条件 / Prerequisites

| 依赖 / Dependency | 版本 / Version | 用途 / Purpose |
|---|---|---|
| OpenClaw | 最新版 / Latest | 主程序 / Main application |
| Node.js | >= 18 | 运行 hooks 脚本 / Run hook scripts |
| Python 3 | >= 3.8 | 运行 Anthropic 代理 / Run Anthropic proxy |
| uv / uvx | 最新版 / Latest | 运行 ChromaDB / Run ChromaDB (auto-installed) |
| GLM API Key | — | 或任意 OpenAI 兼容 API / Or any OpenAI-compatible API |

**获取 GLM API Key / Get GLM API Key:**
- 注册智谱 AI: https://open.bigmodel.cn/
- `glm-4-flash` 模型价格极低，适合记忆生成场景
- glm-4-flash is very low cost, ideal for memory generation use case

---

## 快速安装 / Quick Install

```bash
# 克隆此仓库 / Clone this repo
git clone https://github.com/zxy114/openclaw-claude-mem.git
cd openclaw-claude-mem

# 一键安装 / One-command install
bash install.sh
```

按照提示输入配置参数即可。/ Follow the prompts to enter configuration parameters.

---

## 手动安装 / Manual Install

### 步骤 1：安装 uv (Python 包管理器)
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc  # 或 source ~/.zshrc
```

### 步骤 2：创建数据目录
```bash
mkdir -p ~/.claude-mem
```

### 步骤 3：部署 Anthropic 代理
```bash
cp scripts/anthropic-proxy.py ~/.claude-mem/anthropic-proxy.py
chmod +x ~/.claude-mem/anthropic-proxy.py
```

安装 Flask 依赖：
```bash
pip3 install flask
# 或使用 uv:
uv pip install flask
```

### 步骤 4：创建 claude-glm 包装器
```bash
sudo cp scripts/claude-glm.sh /usr/local/bin/claude-glm
sudo chmod +x /usr/local/bin/claude-glm
```

编辑 `/usr/local/bin/claude-glm`，将 SDK_CLI 路径修改为你实际的 claude-mem 安装路径。

### 步骤 5：创建启动脚本
```bash
cat > ~/.claude-mem/start-worker.sh << 'EOF'
#!/bin/bash
# 检查并启动 Anthropic proxy / Check and start Anthropic proxy
if ! curl -sf http://127.0.0.1:9191/health > /dev/null 2>&1; then
    echo "[start-worker] Starting Anthropic proxy..."
    GLM_API_KEY="your-key-here" \
    GLM_BASE_URL="https://open.bigmodel.cn/api/paas/v4" \
    GLM_MODEL="glm-4-flash" \
    PORT=9191 \
    python3 ~/.claude-mem/anthropic-proxy.py >> ~/.claude-mem/proxy.log 2>&1 &
    sleep 3
fi

# 检查并启动 claude-mem worker / Check and start claude-mem worker
if ! curl -sf http://127.0.0.1:37777/health > /dev/null 2>&1; then
    echo "[start-worker] Starting claude-mem worker..."
    cd ~/.openclaw/workspace/skills/claude-mem
    ~/.bun/bin/bun plugin/scripts/worker-service.cjs start >> ~/.claude-mem/worker.log 2>&1 &
    sleep 5
fi

echo "[start-worker] Services ready."
EOF
chmod +x ~/.claude-mem/start-worker.sh
```

### 步骤 6：配置 settings.json
```bash
cp config/settings-template.json ~/.claude-mem/settings.json
# 根据需要修改配置 / Modify as needed
```

### 步骤 7：安装 hooks
```bash
OPENCLAW_DIR="$HOME/.openclaw"
EXT_DIR="$OPENCLAW_DIR/extensions/claude-mem"
mkdir -p "$EXT_DIR/hooks" "$EXT_DIR/scripts"
cp hooks/hooks.json "$EXT_DIR/hooks/hooks.json"

# 将 hooks.json 中的 OPENCLAW_EXT_DIR 替换为实际路径
sed -i "s|OPENCLAW_EXT_DIR|$EXT_DIR|g" "$EXT_DIR/hooks/hooks.json"

# 从 claude-mem 技能目录复制 bun-runner.js 和 worker-service.cjs
SKILL_DIR="$OPENCLAW_DIR/workspace/skills/claude-mem"
cp "$SKILL_DIR/plugin/scripts/bun-runner.js" "$EXT_DIR/scripts/"
cp "$SKILL_DIR/plugin/scripts/worker-service.cjs" "$EXT_DIR/scripts/"
```

### 步骤 8：更新 openclaw.json
参考 `config/openclaw-plugin-snippet.json`，将 `claude-mem` 加入 plugins.allow 和 plugins.entries。

### 步骤 9：配置开机自启
```bash
(crontab -l 2>/dev/null; echo "@reboot sleep 10 && GLM_API_KEY=your-key python3 ~/.claude-mem/anthropic-proxy.py >> ~/.claude-mem/proxy.log 2>&1 &") | crontab -
(crontab -l 2>/dev/null; echo "@reboot sleep 15 && bash ~/.claude-mem/start-worker.sh") | crontab -
```

---

## 配置参数 / Configuration

### 环境变量 / Environment Variables

| 变量 / Variable | 默认值 / Default | 说明 / Description |
|---|---|---|
| `GLM_API_KEY` | (必填/Required) | GLM 或 OpenAI 兼容 API 密钥 |
| `GLM_BASE_URL` | `https://open.bigmodel.cn/api/paas/v4` | API 基础 URL |
| `GLM_MODEL` | `glm-4-flash` | 使用的模型名称 |
| `PORT` | `9191` | Anthropic 代理监听端口 |

### ~/.claude-mem/settings.json 关键字段

| 字段 / Field | 说明 / Description |
|---|---|
| `CLAUDE_CODE_PATH` | 指向 claude-glm 包装器的路径 |
| `CLAUDE_MEM_PROVIDER` | 使用 `"claude"` |
| `CLAUDE_MEM_WORKER_PORT` | Worker 端口（默认 37777）|
| `CLAUDE_MEM_CHROMA_ENABLED` | 是否启用 ChromaDB 向量存储 |
| `CLAUDE_MEM_CHROMA_MODE` | `"local"` 使用本地 ChromaDB |

---

## 工作原理 / How It Works

### Token 消耗说明 / Token Consumption

**记忆生成（会话结束时）/ Memory Generation (at session end):**
- 每次会话结束，claude-mem 调用 LLM 分析对话历史并生成结构化记忆
- 典型消耗：**500~2000 tokens**（视会话长度而定）
- 使用 `glm-4-flash` 时成本极低（约 ¥0.001~0.004/次）
- At session end, claude-mem calls the LLM to analyze conversation history and generate structured memories
- Typical cost: **500–2000 tokens** per session (varies by session length)

**上下文注入（会话开始时）/ Context Injection (at session start):**
- 新会话开始时，从记忆库检索相关上下文注入到系统提示
- 典型消耗：**~137 tokens**（固定注入格式）
- At new session start, relevant context is retrieved from memory store and injected into system prompt
- Typical cost: **~137 tokens** (fixed injection format)

### Hook 触发时机 / Hook Trigger Timing

| Hook | 触发时机 / Trigger | 动作 / Action |
|---|---|---|
| `Setup` | OpenClaw 初始化 / Initialization | 确保服务运行 / Ensure services running |
| `SessionStart` | 新会话开始 / New session starts | 注入历史上下文 / Inject historical context |
| `UserPromptSubmit` | 用户提交消息 / User submits message | 初始化会话状态 / Initialize session state |
| `PostToolUse` | 工具调用完成 / After each tool use | 记录观察结果 / Record observations |
| `Stop` | 会话暂停/停止 / Session stops | 生成记忆摘要 / Generate memory summary |
| `SessionEnd` | 会话完全结束 / Session fully ends | 完成记忆持久化 / Complete memory persistence |

---

## 故障排查 / Troubleshooting

### 检查服务状态 / Check Service Status

```bash
# 检查 Anthropic 代理 / Check Anthropic proxy
curl -s http://127.0.0.1:9191/health
# 期望输出 / Expected: {"status":"ok","model":"glm-4-flash","base_url":"..."}

# 检查代理模型列表 / Check proxy models
curl -s http://127.0.0.1:9191/v1/models

# 检查 claude-mem worker / Check claude-mem worker
curl -s http://127.0.0.1:37777/health
# 期望输出 / Expected: {"status":"ok"} 或类似 / or similar
```

### 手动启动服务 / Manual Service Start

```bash
# 启动代理 / Start proxy
GLM_API_KEY=your-key GLM_MODEL=glm-4-flash python3 ~/.claude-mem/anthropic-proxy.py &

# 启动 worker / Start worker
bash ~/.claude-mem/start-worker.sh
```

### 查看日志 / View Logs

```bash
# 代理日志 / Proxy logs
tail -f ~/.claude-mem/proxy.log

# Worker 日志 / Worker logs
tail -f ~/.claude-mem/worker.log
```

### 常见问题 / Common Issues

**Q: Worker 启动失败 / Worker fails to start**
A: Worker 必须从 claude-mem 源码目录启动，因为依赖 `bun:sqlite`。确保 `~/.bun/bin/bun` 存在。
Worker must be started from the claude-mem source directory due to `bun:sqlite` dependency. Ensure `~/.bun/bin/bun` exists.

**Q: 代理返回 401 / Proxy returns 401**
A: 检查 GLM_API_KEY 是否正确设置。
Check that GLM_API_KEY is set correctly.

**Q: Hooks 未触发 / Hooks not firing**
A: 检查 hooks.json 中的路径是否已替换为实际绝对路径（不含 `OPENCLAW_EXT_DIR` 占位符）。
Check that paths in hooks.json have been replaced with actual absolute paths (no `OPENCLAW_EXT_DIR` placeholder remaining).

**Q: 记忆未注入 / Memory not injected**
A: 手动测试 hook：
Test hook manually:
```bash
echo '{"session_id":"test-1","prompt":"hello","cwd":"/root"}' | \
CLAUDE_PLUGIN_ROOT=~/.openclaw/extensions/claude-mem \
node ~/.openclaw/extensions/claude-mem/scripts/bun-runner.js \
  ~/.openclaw/extensions/claude-mem/scripts/worker-service.cjs \
  hook claude-code session-init
```

---

## 兼容模型 / Compatible Models

任何支持 OpenAI 兼容接口（`/chat/completions`）的模型均可使用：

Any model supporting OpenAI-compatible API (`/chat/completions`) can be used:

| 提供商 / Provider | 推荐模型 / Recommended Model | BASE_URL |
|---|---|---|
| 智谱 GLM / Zhipu | `glm-4-flash` | `https://open.bigmodel.cn/api/paas/v4` |
| 智谱 GLM / Zhipu | `glm-4-plus` | `https://open.bigmodel.cn/api/paas/v4` |
| OpenAI | `gpt-4o-mini` | `https://api.openai.com/v1` |
| DeepSeek | `deepseek-chat` | `https://api.deepseek.com/v1` |
| Ollama (本地/Local) | `llama3.2` | `http://localhost:11434/v1` |
| 任意兼容 / Any compatible | — | — |

> **推荐 / Recommended:** `glm-4-flash` — 速度快、成本低，非常适合记忆摘要生成场景。
> Fast, cheap, perfect for memory summary generation.

---

## 许可证 / License

MIT

---

*由 OpenClaw + claude-mem + GLM 驱动 / Powered by OpenClaw + claude-mem + GLM*
