#!/bin/bash
# claude-glm: Wrapper that routes claude-mem's LLM calls through the OpenAI-compatible proxy
# Install to: /usr/local/bin/claude-glm
# This allows claude-mem to use GLM (or any OpenAI-compatible LLM) instead of the Anthropic API

PROXY_PORT="${PROXY_PORT:-9191}"
SDK_CLI="$(dirname "$(realpath "$0")")/../../.openclaw/workspace/skills/claude-mem/node_modules/@anthropic-ai/claude-agent-sdk/cli.js"

# Fall back to searching in common locations
if [ ! -f "$SDK_CLI" ]; then
  SDK_CLI="$HOME/.openclaw/workspace/skills/claude-mem/node_modules/@anthropic-ai/claude-agent-sdk/cli.js"
fi

if [ ! -f "$SDK_CLI" ]; then
  echo "ERROR: claude-agent-sdk not found. Is claude-mem installed?" >&2
  exit 1
fi

export ANTHROPIC_BASE_URL="http://127.0.0.1:${PROXY_PORT}"
export ANTHROPIC_API_KEY="local-proxy-key"
exec node "$SDK_CLI" "$@"
