#!/usr/bin/env bash
# claude-controller — multi-backend model switcher for Claude Code
# Supports: Ollama (local) · Anthropic API · OpenAI via LiteLLM · Gemini via LiteLLM
# Usage: claude-controller [--status] [--export] [--list] [--stop-litellm] [--help]
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Config ────────────────────────────────────────────────────────────────────
CACHE_DIR="$HOME/.cache/agentrun"
STATE_FILE="$CACHE_DIR/backend_state.json"
ENV_FILE="$CACHE_DIR/model_env.sh"
KEYS_FILE="$HOME/.config/claude-controller/keys.env"
LITELLM_PORT=11435
OLLAMA_BASE="http://localhost:11434"
LITELLM_CONFIG="$HOME/.config/litellm/config.yaml"
LITELLM_MASTER_KEY="sk-litellm-local"

mkdir -p "$CACHE_DIR" "$(dirname "$KEYS_FILE")"

# ── Backend definitions ───────────────────────────────────────────────────────
# id|label|description|key_var
BACKENDS=(
  "ollama|Ollama (local)|Free · private · your RTX 3090|none"
  "anthropic|Anthropic API|Claude Sonnet/Opus · uses claude login session|ANTHROPIC_API_KEY"
  "openai|OpenAI via LiteLLM|GPT-4o · pay per token|OPENAI_API_KEY"
  "gemini|Gemini via LiteLLM|Gemini 2.0 Flash/Pro · pay per token|GEMINI_API_KEY"
  )

# ── Model lists ───────────────────────────────────────────────────────────────
OLLAMA_REGISTRY=(
  "devstral-small-2:24b|Agentic coding · best tool calls"
  "qwen3-coder:30b|Complex reasoning · large codebases"
  "qwen3-coder:latest|General coding"
  "qwen2.5-coder:14b|Fast fallback · autocomplete"
  "qwen2.5-coder:7b|Lightweight tasks"
  "gemma3:1b-it-qat|Ultra-fast · simple tasks only"
)

ANTHROPIC_REGISTRY=(
  'claude-sonnet-4-6|Claude Sonnet 4.6|200K|$3 / $15 per 1M'
  'claude-opus-4-6|Claude Opus 4.6|200K|$15 / $75 per 1M'
  'claude-haiku-4-5|Claude Haiku 4.5|200K|$0.80 / $4 per 1M'
)

OPENAI_REGISTRY=(
  'gpt-4o|GPT-4o|128K|$2.50 / $10 per 1M'
  'gpt-4o-mini|GPT-4o Mini|128K|$0.15 / $0.60 per 1M'
  'o3-mini|o3 Mini|200K|$1.10 / $4.40 per 1M'
)

GEMINI_REGISTRY=(
  'gemini/gemini-2.0-flash|Gemini 2.0 Flash|1M|$0.10 / $0.40 per 1M'
  'gemini/gemini-2.5-pro|Gemini 2.5 Pro|1M|$1.25 / $10 per 1M'
  'gemini/gemini-2.0-flash-lite|Gemini 2.0 Flash Lite|1M|$0.075 / $0.30 per 1M'
)

# ── State ─────────────────────────────────────────────────────────────────────
save_state() {
  python3 -c "
import json
with open('$STATE_FILE','w') as f:
    json.dump({'backend':'$1','model':'$2'},f)
" 2>/dev/null || echo "{\"backend\":\"$1\",\"model\":\"$2\"}" > "$STATE_FILE"
}

get_state() {
  [[ ! -f "$STATE_FILE" ]] && echo "none" && return
  python3 -c "
import json
d=json.load(open('$STATE_FILE'))
print(d.get('$1','none'))
" 2>/dev/null || echo "none"
}

# ── Key management ────────────────────────────────────────────────────────────
load_key() {
  local key=$1
  local val=""
  [[ -f "$KEYS_FILE" ]] && val=$(grep "^${key}=" "$KEYS_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "")
  [[ -z "$val" ]] && val="${!key:-}"
  echo "$val"
}

prompt_key() {
  local key=$1
  local val; val=$(load_key "$key")
  if [[ -z "$val" ]]; then
    echo -e "\n  ${YELLOW}⚠  $key not found${RESET}" >&2
    echo -e "  ${DIM}Keys file: $KEYS_FILE${RESET}" >&2
    read -rp "  Enter $key: " val
    if [[ -n "$val" ]]; then
      echo "$key=$val" >> "$KEYS_FILE"
      chmod 600 "$KEYS_FILE"
    fi
  fi
  echo "$val"
}

key_status() {
  local key=$1
  [[ "$key" == "none" ]] && echo -e "${GREEN}no key needed${RESET}" && return
  local val; val=$(load_key "$key")
  if [[ -n "$val" ]]; then
    echo -e "${GREEN}key set${RESET}"
  elif [[ "$key" == "ANTHROPIC_API_KEY" ]]; then
    echo -e "${GREEN}login session${RESET}"
  else
    echo -e "${DIM}no key${RESET}"
  fi
}

# ── LiteLLM ───────────────────────────────────────────────────────────────────
litellm_running() {
  # Use nc to check if port is open — no HTTP auth needed
  nc -z 127.0.0.1 "$LITELLM_PORT" 2>/dev/null
}

stop_litellm() {
  # Kill by PID file first
  if [[ -f "$CACHE_DIR/litellm.pid" ]]; then
    local pid; pid=$(cat "$CACHE_DIR/litellm.pid")
    kill "$pid" 2>/dev/null || true
    rm -f "$CACHE_DIR/litellm.pid"
  fi

  # Also kill anything holding the port — handles stale PID files
  local port_pid
  port_pid=$(lsof -ti :"$LITELLM_PORT" 2>/dev/null || true)
  if [[ -n "$port_pid" ]]; then
    kill -9 "$port_pid" 2>/dev/null || true
    echo -e "  ${DIM}LiteLLM stopped (port $LITELLM_PORT freed)${RESET}"
  fi

  # Brief wait for port to be released
  sleep 1
}

start_litellm() {
  local api_key_var=$1 api_key=$2

  if ! command -v litellm > /dev/null 2>&1; then
    echo -e "  ${YELLOW}LiteLLM not installed. Install with:${RESET}"
    echo -e "  ${CYAN}pip install 'litellm[proxy]' --break-system-packages${RESET}"
    read -rp "  Install now? [y/N] " yn
    [[ "$yn" =~ ^[Yy]$ ]] && pip install 'litellm[proxy]' --break-system-packages || exit 1
  fi

  # Ensure config file exists
  if [[ ! -f "$LITELLM_CONFIG" ]]; then
    echo -e "  ${RED}LiteLLM config not found: $LITELLM_CONFIG${RESET}"
    echo -e "  ${DIM}Run: claude-controller --setup-litellm${RESET}"
    exit 1
  fi

  stop_litellm 2>/dev/null || true

  echo -e "  ${DIM}Starting LiteLLM proxy on port $LITELLM_PORT...${RESET}"

  # Export the API key safely
  export "$api_key_var"="$api_key"

  nohup litellm     --config "$LITELLM_CONFIG"     --port "$LITELLM_PORT"     > "$CACHE_DIR/litellm.log" 2>&1 &
  echo $! > "$CACHE_DIR/litellm.pid"

  # Wait up to 45s for LiteLLM to start
  # Note: ((i++)) returns 0 when i=0 which trips set -e, so use i=$((i+1))
  local i=0 ready=false
  echo -ne "  Starting"
  while [[ $i -lt 45 ]]; do
    sleep 1
    i=$((i+1))
    echo -ne "."
    if litellm_running; then
      ready=true
      break
    fi
  done
  echo ""

  # Final check — also accept if port is now listening even if loop timed out
  if [[ "$ready" == "true" ]] || litellm_running; then
    echo -e "  ${GREEN}✓ LiteLLM ready on :$LITELLM_PORT${RESET}"
  else
    echo -e "  ${RED}✗ LiteLLM failed to start${RESET}"
    echo -e "  ${DIM}Last log lines:${RESET}"
    tail -5 "$CACHE_DIR/litellm.log" 2>/dev/null | sed "s/^/    /"
    exit 1
  fi
}

# ── Header ────────────────────────────────────────────────────────────────────
print_header() {
  echo ""
  echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${BLUE}║     Claude Code — Backend & Model Switcher       ║${RESET}"
  echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${RESET}"
  echo ""
  printf "  %-10s %s\n" "Backend:" "$(get_state backend)"
  printf "  %-10s %s\n" "Model:"   "$(get_state model)"
  printf "  %-10s %b\n" "Ollama:"  "$(curl -sf "$OLLAMA_BASE" > /dev/null 2>&1 && echo -e "${GREEN}running${RESET}" || echo -e "${RED}not running${RESET}")"
  printf "  %-10s %b\n" "LiteLLM:" "$(litellm_running && echo -e "${GREEN}running :$LITELLM_PORT${RESET}" || echo -e "${DIM}not running${RESET}")"
  echo ""
}

# ── Pick helpers ──────────────────────────────────────────────────────────────
pick_from_list() {
  local prompt=$1; shift
  local -a items=("$@")
  local total=${#items[@]}
  local idx=1
  for item in "${items[@]}"; do
    echo -e "  ${CYAN}$idx)${RESET} $item"
    idx=$((idx+1))
  done
  echo ""
  read -rp "  $prompt [1-$total / q]: " choice
  [[ "$choice" == "q" ]] && exit 0
  if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt "$total" ]]; then
    echo -e "  ${RED}Invalid choice${RESET}" && exit 1
  fi
  echo "${items[$((choice-1))]}"
}

# ── Backend picker ────────────────────────────────────────────────────────────
SELECTED_BACKEND=""
pick_backend() {
  echo -e "  ${BOLD}Select backend:${RESET}"
  echo ""
  printf "  %-3s %-22s %-36s %s\n" "No." "Backend" "Description" "API Key"
  printf "  %-3s %-22s %-36s %s\n" "───" "─────────────────────" "───────────────────────────────────" "───────"

  local idx=1
  for entry in "${BACKENDS[@]}"; do
    IFS='|' read -r id label desc key_var <<< "$entry"
    printf "  ${CYAN}%-3s${RESET} %-22s %-36s %b\n" \
      "$idx" "$label" "$desc" "$(key_status "$key_var")"
    idx=$((idx+1))
  done

  echo ""
  read -rp "  Select backend [1-${#BACKENDS[@]} / q]: " choice
  [[ "$choice" == "q" ]] && exit 0
  if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt "${#BACKENDS[@]}" ]]; then
    echo -e "  ${RED}Invalid choice${RESET}" && exit 1
  fi
  IFS='|' read -r id _ _ _ <<< "${BACKENDS[$((choice-1))]}"
  SELECTED_BACKEND="$id"
}

# ── Model pickers ─────────────────────────────────────────────────────────────
SELECTED_MODEL=""
pick_ollama_model() {
  local available; available=$(ollama list 2>/dev/null | awk 'NR>1 {print $1}' || echo "")

  echo ""
  echo -e "  ${BOLD}Local models:${RESET}"
  echo ""
  printf "  %-3s %-32s %-10s %s\n" "No." "Model" "Size" "Best for"
  printf "  %-3s %-32s %-10s %s\n" "───" "───────────────────────────────" "─────────" "──────────────────────────"

  local idx=1
  local model_list=()

  for entry in "${OLLAMA_REGISTRY[@]}"; do
    IFS='|' read -r model best_for <<< "$entry"
    if echo "$available" | grep -qx "$model" 2>/dev/null; then
      local size; size=$(ollama list 2>/dev/null | awk -v m="$model" '$1==m {print $3,$4}')
      printf "  ${CYAN}%-3s${RESET} %-32s ${DIM}%-10s${RESET} %s\n" "$idx" "$model" "$size" "$best_for"
      model_list+=("$model")
      idx=$((idx+1))
    fi
  done

  while IFS= read -r model; do
    [[ -z "$model" ]] && continue
    local found=false
    for entry in "${OLLAMA_REGISTRY[@]}"; do
      IFS='|' read -r reg _ <<< "$entry"
      [[ "$reg" == "$model" ]] && found=true && break
    done
    if [[ "$found" == "false" ]]; then
      local size; size=$(ollama list 2>/dev/null | awk -v m="$model" '$1==m {print $3,$4}')
      printf "  ${CYAN}%-3s${RESET} %-32s ${DIM}%-10s${RESET} %s\n" "$idx" "$model" "$size" "custom"
      model_list+=("$model")
      idx=$((idx+1))
    fi
  done <<< "$available"

  [[ ${#model_list[@]} -eq 0 ]] && \
    echo -e "  ${RED}No models pulled. Run: ollama pull devstral-small-2:24b${RESET}" && exit 1

  echo ""
  read -rp "  Select model [1-${#model_list[@]}]: " choice
  SELECTED_MODEL="${model_list[$((choice-1))]}"
}

pick_api_model() {
  local -n reg=$1
  echo ""
  printf "  %-3s %-45s %-8s %s\n" "No." "Model" "Context" "Cost (in/out per 1M)"
  printf "  %-3s %-45s %-8s %s\n" "───" "────────────────────────────────────────────" "───────" "─────────────────────────"
  local idx=1
  local model_list=()
  for entry in "${reg[@]}"; do
    IFS='|' read -ra parts <<< "$entry"
    local model="${parts[0]}" display="${parts[1]}" ctx="${parts[2]:-}" cost="${parts[3]:-}"
    printf "  ${CYAN}%-3s${RESET} %-45s ${DIM}%-8s${RESET} %s\n" "$idx" "$display" "$ctx" "$cost"
    model_list+=("$model")
    idx=$((idx+1))
  done
  echo ""
  read -rp "  Select model [1-${#model_list[@]}]: " choice
  SELECTED_MODEL="${model_list[$((choice-1))]}"
}

# ── Apply functions ───────────────────────────────────────────────────────────
write_env() { cat > "$ENV_FILE"; chmod 600 "$ENV_FILE"; }

print_result() {
  local backend=$1 model=$2
  echo ""
  echo -e "  ${GREEN}✓ Switched to:${RESET} ${BOLD}$backend${RESET} — ${CYAN}$model${RESET}"
  echo ""
}

apply_ollama() {
  local model=$1
  stop_litellm 2>/dev/null || true
  save_state "ollama" "$model"
  write_env << EOF
export ANTHROPIC_AUTH_TOKEN=ollama
export ANTHROPIC_API_KEY=''
export ANTHROPIC_BASE_URL=http://localhost:11434
export CLAUDE_MODEL=$model
unset OPENAI_API_KEY 2>/dev/null || true
unset GEMINI_API_KEY 2>/dev/null || true
EOF
  print_result "Ollama" "$model"
}

apply_anthropic() {
  local model=$1
  stop_litellm 2>/dev/null || true
  save_state "anthropic" "$model"

  # Check if user has a stored API key — if not, fall back to claude login session
  local key; key=$(load_key ANTHROPIC_API_KEY)

  if [[ -n "$key" ]]; then
    # Use API key if available
    write_env << EOF
export ANTHROPIC_API_KEY=$key
export CLAUDE_MODEL=$model
unset ANTHROPIC_AUTH_TOKEN 2>/dev/null || true
unset ANTHROPIC_BASE_URL 2>/dev/null || true
EOF
    echo -e "  ${DIM}Using Anthropic API key${RESET}"
  else
    # Fall back to existing claude login session — just clear Ollama overrides
    write_env << EOF
unset ANTHROPIC_AUTH_TOKEN 2>/dev/null || true
unset ANTHROPIC_BASE_URL 2>/dev/null || true
unset ANTHROPIC_API_KEY 2>/dev/null || true
export CLAUDE_MODEL=$model
EOF
    echo -e "  ${DIM}Using existing claude login session${RESET}"
  fi

  print_result "Anthropic API" "$model"
}

apply_openai() {
  local model=$1
  local key; key=$(prompt_key OPENAI_API_KEY)
  [[ -z "$key" ]] && echo -e "  ${RED}No API key${RESET}" && exit 1
  start_litellm "OPENAI_API_KEY" "$key"
  save_state "openai" "$model"
  write_env << EOF
export ANTHROPIC_AUTH_TOKEN=$LITELLM_MASTER_KEY
export ANTHROPIC_API_KEY=""
export ANTHROPIC_BASE_URL=http://localhost:$LITELLM_PORT
export OPENAI_API_KEY=$key
export CLAUDE_MODEL=$model
EOF
  print_result "OpenAI via LiteLLM" "$model"
}

apply_gemini() {
  local model=$1
  local key; key=$(prompt_key GEMINI_API_KEY)
  [[ -z "$key" ]] && echo -e "  ${RED}No API key${RESET}" && exit 1
  start_litellm "GEMINI_API_KEY" "$key"
  save_state "gemini" "$model"
  write_env << EOF
export ANTHROPIC_AUTH_TOKEN=$LITELLM_MASTER_KEY
export ANTHROPIC_API_KEY=""
export ANTHROPIC_BASE_URL=http://localhost:$LITELLM_PORT
export GEMINI_API_KEY=$key
export CLAUDE_MODEL=$model
EOF
  print_result "Gemini via LiteLLM" "$model"
}

# ── Launch after applying ────────────────────────────────────────────────────
launch_claude() {
  local backend=$1 model=$2

  # Source the env file into current shell
  # shellcheck disable=SC1090
  source "$ENV_FILE"

  echo -e "  ${BOLD}Launching Claude Code...${RESET}"
  echo ""

  case "$backend" in
    ollama)
      exec ollama launch claude --model "$model"
      ;;
    *)
      exec claude --model "$model"
      ;;
  esac
}

# ── Main interactive flow ─────────────────────────────────────────────────────
mode_interactive() {
  print_header
  pick_backend
  echo ""

  case "$SELECTED_BACKEND" in
    ollama)
      pick_ollama_model
      apply_ollama "$SELECTED_MODEL"
      ;;
    anthropic)
      pick_api_model ANTHROPIC_REGISTRY
      apply_anthropic "$SELECTED_MODEL"
      ;;
    openai)
      pick_api_model OPENAI_REGISTRY
      apply_openai "$SELECTED_MODEL"
      ;;
    gemini)
      pick_api_model GEMINI_REGISTRY
      apply_gemini "$SELECTED_MODEL"
      ;;
  esac

  launch_claude "$SELECTED_BACKEND" "$SELECTED_MODEL"
}

# ── Entry point ───────────────────────────────────────────────────────────────
case "${1:-}" in
  --status)
    print_header
    [[ -f "$ENV_FILE" ]] && echo -e "  ${BOLD}Active env:${RESET}" && \
      grep "^export" "$ENV_FILE" | sed 's/export /    /'
    echo ""
    ;;
  --export)
    [[ -f "$ENV_FILE" ]] && cat "$ENV_FILE" || \
      echo "# No backend selected yet — run: claude-controller"
    ;;
  --stop-litellm)
    stop_litellm
    ;;
  --setup-litellm)
    mkdir -p "$(dirname "$LITELLM_CONFIG")"
    cat > "$LITELLM_CONFIG" << 'EOF'
model_list:
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY
  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: os.environ/OPENAI_API_KEY
  - model_name: o3-mini
    litellm_params:
      model: openai/o3-mini
      api_key: os.environ/OPENAI_API_KEY
  - model_name: gemini/gemini-2.0-flash
    litellm_params:
      model: gemini/gemini-2.0-flash
      api_key: os.environ/GEMINI_API_KEY
  - model_name: gemini/gemini-2.5-pro
    litellm_params:
      model: gemini/gemini-2.5-pro
      api_key: os.environ/GEMINI_API_KEY
  - model_name: gemini/gemini-2.0-flash-lite
    litellm_params:
      model: gemini/gemini-2.0-flash-lite
      api_key: os.environ/GEMINI_API_KEY
general_settings:
  master_key: sk-litellm-local
EOF
    echo -e "${GREEN}✓ LiteLLM config written to $LITELLM_CONFIG${RESET}"
    echo -e "${DIM}Add your API keys to $KEYS_FILE${RESET}"
    ;;
  --list)
    echo ""
    echo -e "${BOLD}Backends:${RESET}"
    for entry in "${BACKENDS[@]}"; do
      IFS='|' read -r id label desc key_var <<< "$entry"
      printf "  ${CYAN}%-12s${RESET} %s\n" "$id" "$desc"
    done
    echo ""
    echo -e "${BOLD}Keys file:${RESET} $KEYS_FILE"
    echo ""
    ;;
  --help)
    cat << 'EOF'

Usage: claude-controller [option]

  (no args)        Pick backend + model, then launch Claude Code automatically
  --status         Show current backend, model, and active env vars
  --export         Print env vars for sourcing into current shell
  --list           List all supported backends
  --stop-litellm   Stop the LiteLLM proxy
  --help           Show this help

Workflow:
  claude-controller          # pick backend + model → launches Claude Code

That's it. One command does everything.

To re-use the last selection in a new shell without the picker:
  source <(claude-controller --export) && ollama launch claude --model $CLAUDE_MODEL  # Ollama
  source <(claude-controller --export) && claude --model $CLAUDE_MODEL                # others

API keys are stored in: ~/.config/claude-controller/keys.env
LiteLLM log:            ~/.cache/agentrun/litellm.log

EOF
    ;;
  *)
    mode_interactive
    ;;
esac