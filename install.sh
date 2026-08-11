#!/bin/bash
# =============================================================================
# OpenClaw Persistent Memory System Installer
# Installs claude-mem + GLM proxy for OpenClaw
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "============================================================"
echo "  OpenClaw Persistent Memory Installer"
echo "  claude-mem + GLM proxy setup"
echo "============================================================"
echo ""

# =============================================================================
# Step 1: Collect configuration from user
# =============================================================================
log_info "Step 1/10: Configuration"
echo ""

read -p "GLM_API_KEY (required): " GLM_API_KEY
if [ -z "$GLM_API_KEY" ]; then
    log_error "GLM_API_KEY is required. Obtain one from https://open.bigmodel.cn/"
    exit 1
fi

read -p "GLM_BASE_URL [https://open.bigmodel.cn/api/paas/v4]: " GLM_BASE_URL
GLM_BASE_URL="${GLM_BASE_URL:-https://open.bigmodel.cn/api/paas/v4}"

read -p "GLM_MODEL [glm-4-flash]: " GLM_MODEL
GLM_MODEL="${GLM_MODEL:-glm-4-flash}"

read -p "PROXY_PORT [9191]: " PROXY_PORT
PROXY_PORT="${PROXY_PORT:-9191}"

read -p "WORKER_PORT [37777]: " WORKER_PORT
WORKER_PORT="${WORKER_PORT:-37777}"

echo ""
log_info "Configuration summary:"
echo "  GLM_BASE_URL  = $GLM_BASE_URL"
echo "  GLM_MODEL     = $GLM_MODEL"
echo "  PROXY_PORT    = $PROXY_PORT"
echo "  WORKER_PORT   = $WORKER_PORT"
echo ""

# =============================================================================
# Step 2: Detect OpenClaw directory
# =============================================================================
log_info "Step 2/10: Detecting OpenClaw directory"

if [ -n "$OPENCLAW_DIR" ]; then
    log_info "Using OPENCLAW_DIR from environment: $OPENCLAW_DIR"
elif [ -d "$HOME/.openclaw" ]; then
    OPENCLAW_DIR="$HOME/.openclaw"
    log_success "Found OpenClaw at $OPENCLAW_DIR"
else
    read -p "OpenClaw directory not found at ~/.openclaw. Enter path [~/.openclaw]: " OPENCLAW_DIR
    OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
fi

if [ ! -d "$OPENCLAW_DIR" ]; then
    log_error "OpenClaw directory does not exist: $OPENCLAW_DIR"
    log_error "Please install OpenClaw first."
    exit 1
fi

SKILL_DIR="$OPENCLAW_DIR/workspace/skills/claude-mem"
EXT_DIR="$OPENCLAW_DIR/extensions/claude-mem"

# =============================================================================
# Step 3: Check claude-mem is installed in openclaw workspace
# =============================================================================
log_info "Step 3/10: Checking claude-mem installation"

if [ ! -d "$SKILL_DIR" ]; then
    log_error "claude-mem skill not found at: $SKILL_DIR"
    log_error "Please install the claude-mem skill in OpenClaw first."
    log_warn "In OpenClaw, run: /install claude-mem"
    exit 1
fi

if [ ! -f "$SKILL_DIR/plugin/scripts/worker-service.cjs" ]; then
    log_error "worker-service.cjs not found in claude-mem skill directory."
    log_error "Your claude-mem installation may be incomplete."
    exit 1
fi

log_success "claude-mem found at: $SKILL_DIR"

# =============================================================================
# Step 4: Install uv if not present
# =============================================================================
log_info "Step 4/10: Checking uv (Python package manager)"

if command -v uv &>/dev/null; then
    log_success "uv is already installed: $(uv --version)"
else
    log_info "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Add uv to PATH for this session
    export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
    if command -v uv &>/dev/null; then
        log_success "uv installed successfully"
    else
        log_warn "uv installation may require shell restart. Continuing..."
    fi
fi

# Install Flask for the proxy
log_info "Installing Flask..."
if command -v pip3 &>/dev/null; then
    pip3 install flask --quiet && log_success "Flask installed"
elif command -v uv &>/dev/null; then
    uv pip install flask --quiet && log_success "Flask installed via uv"
else
    log_warn "Could not install Flask automatically. Please run: pip3 install flask"
fi

# =============================================================================
# Step 5: Create ~/.claude-mem/ directory and deploy files
# =============================================================================
log_info "Step 5/10: Creating ~/.claude-mem directory"

mkdir -p "$HOME/.claude-mem"
log_success "Created $HOME/.claude-mem"

# Copy anthropic-proxy.py
if [ -f "$SCRIPT_DIR/scripts/anthropic-proxy.py" ]; then
    cp "$SCRIPT_DIR/scripts/anthropic-proxy.py" "$HOME/.claude-mem/anthropic-proxy.py"
    chmod +x "$HOME/.claude-mem/anthropic-proxy.py"
    log_success "Deployed anthropic-proxy.py"
else
    log_error "scripts/anthropic-proxy.py not found in package. Cannot continue."
    exit 1
fi

# =============================================================================
# Step 6: Create /usr/local/bin/claude-glm wrapper
# =============================================================================
log_info "Step 6/10: Creating claude-glm wrapper"

SDK_CLI="$SKILL_DIR/node_modules/@anthropic-ai/claude-agent-sdk/cli.js"

if [ ! -f "$SDK_CLI" ]; then
    log_warn "claude-agent-sdk cli.js not found at expected path."
    log_warn "Searching for it..."
    SDK_CLI=$(find "$SKILL_DIR" -name "cli.js" -path "*claude-agent-sdk*" 2>/dev/null | head -1)
    if [ -z "$SDK_CLI" ]; then
        log_error "Could not locate claude-agent-sdk cli.js. Is claude-mem fully installed?"
        exit 1
    fi
    log_success "Found cli.js at: $SDK_CLI"
fi

cat > /tmp/claude-glm-wrapper << WRAPPER_EOF
#!/bin/bash
# claude-glm: Routes claude-mem LLM calls through the OpenAI-compatible proxy
# Auto-generated by openclaw-claude-mem installer

export ANTHROPIC_BASE_URL="http://127.0.0.1:${PROXY_PORT}"
export ANTHROPIC_API_KEY="local-proxy-key"
exec node "${SDK_CLI}" "\$@"
WRAPPER_EOF

if sudo cp /tmp/claude-glm-wrapper /usr/local/bin/claude-glm && sudo chmod +x /usr/local/bin/claude-glm; then
    log_success "Created /usr/local/bin/claude-glm"
else
    log_warn "Could not write to /usr/local/bin (no sudo?). Installing to ~/.local/bin/claude-glm instead."
    mkdir -p "$HOME/.local/bin"
    cp /tmp/claude-glm-wrapper "$HOME/.local/bin/claude-glm"
    chmod +x "$HOME/.local/bin/claude-glm"
    CLAUDE_GLM_PATH="$HOME/.local/bin/claude-glm"
    log_success "Created $CLAUDE_GLM_PATH"
fi
CLAUDE_GLM_PATH="${CLAUDE_GLM_PATH:-/usr/local/bin/claude-glm}"

# =============================================================================
# Step 7: Create ~/.claude-mem/start-worker.sh
# =============================================================================
log_info "Step 7/10: Creating start-worker.sh"

cat > "$HOME/.claude-mem/start-worker.sh" << WORKER_EOF
#!/bin/bash
# start-worker.sh — Ensures anthropic-proxy and claude-mem worker are running
# Auto-generated by openclaw-claude-mem installer

PROXY_PORT="${PROXY_PORT}"
WORKER_PORT="${WORKER_PORT}"
SKILL_DIR="${SKILL_DIR}"

log() { echo "[start-worker] \$(date '+%Y-%m-%d %H:%M:%S') \$1"; }

# --- Start Anthropic proxy if not running ---
if ! curl -sf "http://127.0.0.1:\${PROXY_PORT}/health" > /dev/null 2>&1; then
    log "Starting Anthropic-to-GLM proxy on port \${PROXY_PORT}..."
    GLM_API_KEY="${GLM_API_KEY}" \\
    GLM_BASE_URL="${GLM_BASE_URL}" \\
    GLM_MODEL="${GLM_MODEL}" \\
    PORT="\${PROXY_PORT}" \\
    python3 "\$HOME/.claude-mem/anthropic-proxy.py" >> "\$HOME/.claude-mem/proxy.log" 2>&1 &
    sleep 3
    if curl -sf "http://127.0.0.1:\${PROXY_PORT}/health" > /dev/null 2>&1; then
        log "Proxy started successfully."
    else
        log "WARNING: Proxy may not have started. Check \$HOME/.claude-mem/proxy.log"
    fi
else
    log "Proxy already running on port \${PROXY_PORT}."
fi

# --- Start claude-mem worker if not running ---
if ! curl -sf "http://127.0.0.1:\${WORKER_PORT}/health" > /dev/null 2>&1; then
    log "Starting claude-mem worker on port \${WORKER_PORT}..."
    if [ ! -d "\${SKILL_DIR}" ]; then
        log "ERROR: SKILL_DIR not found: \${SKILL_DIR}"
        exit 1
    fi
    cd "\${SKILL_DIR}"
    "\$HOME/.bun/bin/bun" plugin/scripts/worker-service.cjs start >> "\$HOME/.claude-mem/worker.log" 2>&1 &
    sleep 5
    if curl -sf "http://127.0.0.1:\${WORKER_PORT}/health" > /dev/null 2>&1; then
        log "Worker started successfully."
    else
        log "WARNING: Worker may not have started. Check \$HOME/.claude-mem/worker.log"
    fi
else
    log "Worker already running on port \${WORKER_PORT}."
fi

log "All services checked."
WORKER_EOF

chmod +x "$HOME/.claude-mem/start-worker.sh"
log_success "Created ~/.claude-mem/start-worker.sh"

# =============================================================================
# Step 8: Update ~/.claude-mem/settings.json
# =============================================================================
log_info "Step 8/10: Updating settings.json"

SETTINGS_FILE="$HOME/.claude-mem/settings.json"

if [ -f "$SETTINGS_FILE" ]; then
    log_info "settings.json already exists. Updating key fields only..."
    # Use Python to safely update JSON
    python3 << PYEOF
import json, sys

settings_path = "$SETTINGS_FILE"
try:
    with open(settings_path, 'r') as f:
        settings = json.load(f)
except:
    settings = {}

# Apply our required settings
settings["CLAUDE_CODE_PATH"] = "$CLAUDE_GLM_PATH"
settings["CLAUDE_MEM_PROVIDER"] = "claude"
settings["CLAUDE_MEM_WORKER_PORT"] = "$WORKER_PORT"
settings["CLAUDE_MEM_WORKER_HOST"] = "127.0.0.1"
settings["CLAUDE_MEM_CHROMA_ENABLED"] = "true"
settings["CLAUDE_MEM_CHROMA_MODE"] = "local"

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
print("settings.json updated")
PYEOF
else
    cat > "$SETTINGS_FILE" << SETTINGS_EOF
{
  "CLAUDE_CODE_PATH": "${CLAUDE_GLM_PATH}",
  "CLAUDE_MEM_PROVIDER": "claude",
  "CLAUDE_MEM_WORKER_PORT": "${WORKER_PORT}",
  "CLAUDE_MEM_WORKER_HOST": "127.0.0.1",
  "CLAUDE_MEM_CHROMA_ENABLED": "true",
  "CLAUDE_MEM_CHROMA_MODE": "local"
}
SETTINGS_EOF
fi

log_success "settings.json configured"

# =============================================================================
# Step 9: Install hooks and scripts to extensions directory
# =============================================================================
log_info "Step 9/10: Installing hooks and extension scripts"

mkdir -p "$EXT_DIR/hooks"
mkdir -p "$EXT_DIR/scripts"

# Copy hooks.json and replace placeholder
cp "$SCRIPT_DIR/hooks/hooks.json" "$EXT_DIR/hooks/hooks.json"
# Replace OPENCLAW_EXT_DIR placeholder with actual path
sed -i "s|OPENCLAW_EXT_DIR|${EXT_DIR}|g" "$EXT_DIR/hooks/hooks.json"
log_success "Installed hooks.json (with resolved paths)"

# Copy bun-runner.js from the skill directory
BUN_RUNNER_SRC="$SKILL_DIR/plugin/scripts/bun-runner.js"
if [ -f "$BUN_RUNNER_SRC" ]; then
    cp "$BUN_RUNNER_SRC" "$EXT_DIR/scripts/bun-runner.js"
    log_success "Copied bun-runner.js"
else
    log_warn "bun-runner.js not found at $BUN_RUNNER_SRC — hooks may not work"
fi

# Copy worker-service.cjs from the skill directory
WORKER_CJS_SRC="$SKILL_DIR/plugin/scripts/worker-service.cjs"
if [ -f "$WORKER_CJS_SRC" ]; then
    cp "$WORKER_CJS_SRC" "$EXT_DIR/scripts/worker-service.cjs"
    log_success "Copied worker-service.cjs"
else
    log_warn "worker-service.cjs not found at $WORKER_CJS_SRC — hooks may not work"
fi

# Copy smart-install.js if present
SMART_INSTALL_SRC="$SKILL_DIR/plugin/scripts/smart-install.js"
if [ -f "$SMART_INSTALL_SRC" ]; then
    cp "$SMART_INSTALL_SRC" "$EXT_DIR/scripts/smart-install.js"
    log_success "Copied smart-install.js"
fi

# Update openclaw.json
OPENCLAW_JSON="$OPENCLAW_DIR/openclaw.json"
if [ -f "$OPENCLAW_JSON" ]; then
    log_info "Updating $OPENCLAW_JSON..."
    python3 << PYEOF
import json, sys

config_path = "$OPENCLAW_JSON"
try:
    with open(config_path, 'r') as f:
        config = json.load(f)
except Exception as e:
    print(f"Could not read openclaw.json: {e}", file=sys.stderr)
    sys.exit(1)

if "plugins" not in config:
    config["plugins"] = {}

if "allow" not in config["plugins"]:
    config["plugins"]["allow"] = []
if "claude-mem" not in config["plugins"]["allow"]:
    config["plugins"]["allow"].append("claude-mem")
    print("Added claude-mem to plugins.allow")
else:
    print("claude-mem already in plugins.allow")

if "entries" not in config["plugins"]:
    config["plugins"]["entries"] = {}
if "claude-mem" not in config["plugins"]["entries"]:
    config["plugins"]["entries"]["claude-mem"] = {"enabled": True}
    print("Added claude-mem to plugins.entries")
else:
    config["plugins"]["entries"]["claude-mem"]["enabled"] = True
    print("Updated claude-mem in plugins.entries")

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
print("openclaw.json updated successfully")
PYEOF
    log_success "openclaw.json updated"
else
    log_warn "openclaw.json not found at $OPENCLAW_JSON — skipping plugin registration"
    log_warn "Manually add claude-mem to your openclaw.json using config/openclaw-plugin-snippet.json as reference"
fi

# Add crontab entries
log_info "Adding crontab entries for autostart..."
(crontab -l 2>/dev/null | grep -v "anthropic-proxy.py" | grep -v "start-worker.sh"; \
 echo "@reboot sleep 10 && GLM_API_KEY=${GLM_API_KEY} GLM_BASE_URL=${GLM_BASE_URL} GLM_MODEL=${GLM_MODEL} PORT=${PROXY_PORT} python3 \$HOME/.claude-mem/anthropic-proxy.py >> \$HOME/.claude-mem/proxy.log 2>&1 &"; \
 echo "@reboot sleep 15 && bash \$HOME/.claude-mem/start-worker.sh >> \$HOME/.claude-mem/worker.log 2>&1") | crontab -
log_success "Crontab entries added"

# =============================================================================
# Step 10: Start services and health check
# =============================================================================
log_info "Step 10/10: Starting services"

# Start proxy
log_info "Starting Anthropic proxy..."
GLM_API_KEY="$GLM_API_KEY" \
GLM_BASE_URL="$GLM_BASE_URL" \
GLM_MODEL="$GLM_MODEL" \
PORT="$PROXY_PORT" \
python3 "$HOME/.claude-mem/anthropic-proxy.py" >> "$HOME/.claude-mem/proxy.log" 2>&1 &

sleep 4

# Start worker
log_info "Starting claude-mem worker..."
bash "$HOME/.claude-mem/start-worker.sh"

sleep 3

# Health checks
echo ""
log_info "Running health checks..."

PROXY_OK=false
WORKER_OK=false

if curl -sf "http://127.0.0.1:${PROXY_PORT}/health" > /dev/null 2>&1; then
    PROXY_HEALTH=$(curl -s "http://127.0.0.1:${PROXY_PORT}/health")
    log_success "Anthropic proxy is healthy: $PROXY_HEALTH"
    PROXY_OK=true
else
    log_error "Anthropic proxy health check FAILED. Check: $HOME/.claude-mem/proxy.log"
fi

if curl -sf "http://127.0.0.1:${WORKER_PORT}/health" > /dev/null 2>&1; then
    log_success "claude-mem worker is healthy"
    WORKER_OK=true
else
    log_warn "claude-mem worker health check did not respond (may still be starting)."
    log_warn "Check: $HOME/.claude-mem/worker.log"
fi

# =============================================================================
# Final summary
# =============================================================================
echo ""
echo "============================================================"
if $PROXY_OK && $WORKER_OK; then
    echo -e "${GREEN}  Installation complete! All services running.${NC}"
else
    echo -e "${YELLOW}  Installation complete with warnings.${NC}"
    echo "  Check logs in ~/.claude-mem/ if services did not start."
fi
echo "============================================================"
echo ""
echo "  Proxy:    http://127.0.0.1:${PROXY_PORT}/health"
echo "  Worker:   http://127.0.0.1:${WORKER_PORT}/health"
echo "  Logs:     ~/.claude-mem/proxy.log"
echo "            ~/.claude-mem/worker.log"
echo ""
echo "  Data:     ~/.claude-mem/claude-mem.db  (SQLite memories)"
echo "            ~/.claude-mem/chroma/        (ChromaDB vectors)"
echo ""
echo "  Restart OpenClaw to activate the memory hooks."
echo ""
echo "  To manually restart services:"
echo "    bash ~/.claude-mem/start-worker.sh"
echo ""
