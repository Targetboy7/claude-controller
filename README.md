# claude-controller

A single command that lets you switch Claude Code between different AI backends and launches it automatically. No manual env var juggling, no separate terminal windows.

---

## What it does

```
claude-controller
  → pick backend (Ollama / Anthropic / OpenAI / Gemini)
  → pick model
  → starts LiteLLM proxy if needed
  → launches Claude Code
```

That's it. One command.

---

## Supported backends

| Backend | How it connects | API key needed |
|---------|----------------|----------------|
| Ollama (local) | Direct to `localhost:11434` | No — free |
| Anthropic API | Direct to Anthropic | Uses `claude login` session |
| OpenAI via LiteLLM | LiteLLM proxy → OpenAI | Yes — `OPENAI_API_KEY` |
| Gemini via LiteLLM | LiteLLM proxy → Gemini | Yes — `GEMINI_API_KEY` |

---

## Requirements

- Ubuntu 22.04+ (tested on 24.04)
- [Claude Code CLI](https://claude.ai/install) installed
- [Ollama](https://ollama.com) running as a systemd service (for local backend)
- Python 3.x, `curl`, `nc` (netcat), `lsof`
- For OpenAI/Gemini: LiteLLM with proxy support

---

## Installation

### 1. Copy the script
```bash
cp claude-controller.sh ~/workouts/claude-wrapper/
chmod +x ~/workouts/claude-wrapper/claude-controller.sh
ln -sf ~/workouts/claude-wrapper/claude-controller.sh ~/.local/bin/claude-controller
```

### 2. Ensure `~/.local/bin` is on your PATH
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### 3. Install LiteLLM (for OpenAI and Gemini backends)
```bash
pip install 'litellm[proxy]' --break-system-packages
```

### 4. Generate the LiteLLM config
```bash
claude-controller --setup-litellm
```

This creates `~/.config/litellm/config.yaml` with all OpenAI and Gemini models pre-configured.

### 5. Add API keys
```bash
mkdir -p ~/.config/claude-controller
cat >> ~/.config/claude-controller/keys.env << 'EOF'
OPENAI_API_KEY=sk-your-openai-key-here
GEMINI_API_KEY=your-gemini-key-here
EOF
chmod 600 ~/.config/claude-controller/keys.env
```

Get keys from:
- OpenAI: https://platform.openai.com/api-keys
- Gemini: https://aistudio.google.com/apikey

### 6. Verify Ollama is running
```bash
sudo systemctl status ollama
ollama list
```

---

## Usage

### Normal workflow — just run it
```bash
claude-controller
```

Pick a backend, pick a model — Claude Code launches automatically.

### Other commands
```bash
claude-controller --status         # show current backend, model, env vars
claude-controller --list           # list all supported backends
claude-controller --stop-litellm   # stop the LiteLLM proxy
claude-controller --setup-litellm  # regenerate LiteLLM config file
claude-controller --help           # show help
```

### Apply selection to current shell (without launching)
```bash
source <(claude-controller --export)
# Then manually launch:
ollama launch claude --model $CLAUDE_MODEL   # Ollama
claude --model $CLAUDE_MODEL                 # API backends
```

---

## LiteLLM config

The LiteLLM config lives at `~/.config/litellm/config.yaml`. The key setting that makes Claude Code work with non-Anthropic models is `drop_params: true` — it silently drops parameters that Claude Code sends but Gemini/OpenAI don't understand.

```yaml
model_list:
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY

  - model_name: gemini/gemini-2.0-flash
    litellm_params:
      model: gemini/gemini-2.0-flash
      api_key: os.environ/GEMINI_API_KEY

general_settings:
  master_key: sk-litellm-local

litellm_settings:
  drop_params: true          # ← required for Claude Code compatibility
```

---

## How it works internally

```
claude-controller
    │
    ├─ Ollama ──────────────────────────────► Ollama :11434
    │   ANTHROPIC_AUTH_TOKEN=ollama            (local models)
    │   ANTHROPIC_BASE_URL=localhost:11434
    │
    ├─ Anthropic ───────────────────────────► Anthropic API
    │   uses existing claude login session      (claude-sonnet, opus)
    │   no BASE_URL override
    │
    ├─ OpenAI ──────────────────────────────► LiteLLM :11435 ──► OpenAI
    │   ANTHROPIC_AUTH_TOKEN=sk-litellm-local  (gpt-4o, o3-mini)
    │   ANTHROPIC_BASE_URL=localhost:11435
    │
    └─ Gemini ──────────────────────────────► LiteLLM :11435 ──► Gemini
        ANTHROPIC_AUTH_TOKEN=sk-litellm-local  (gemini-2.0-flash, 2.5-pro)
        ANTHROPIC_BASE_URL=localhost:11435
```

LiteLLM acts as a translation layer — Claude Code speaks Anthropic's API format, and LiteLLM converts it to whatever format OpenAI or Gemini expects.

---

## File locations

| File | Purpose |
|------|---------|
| `~/.config/claude-controller/keys.env` | API keys storage (chmod 600) |
| `~/.config/litellm/config.yaml` | LiteLLM model definitions |
| `~/.cache/agentrun/backend_state.json` | Last selected backend + model |
| `~/.cache/agentrun/model_env.sh` | Exported env vars for current selection |
| `~/.cache/agentrun/litellm.log` | LiteLLM proxy logs |
| `~/.cache/agentrun/litellm.pid` | LiteLLM process ID |

---

## Troubleshooting

**`claude-controller: command not found`**
```bash
export PATH="$HOME/.local/bin:$PATH"
source ~/.bashrc
```

**LiteLLM port already in use**
```bash
sudo lsof -ti :11435 | xargs kill -9 2>/dev/null || true
claude-controller
```

**Gemini: `API key not valid`**

The Gemini key in `keys.env` isn't reaching LiteLLM. Hardcode it in the config:
```bash
# Get your key
KEY=$(grep GEMINI_API_KEY ~/.config/claude-controller/keys.env | cut -d= -f2-)
# Update config to use literal key instead of os.environ reference
sed -i "s|os.environ/GEMINI_API_KEY|$KEY|g" ~/.config/litellm/config.yaml
# Restart LiteLLM
sudo lsof -ti :11435 | xargs kill -9 2>/dev/null || true
claude-controller
```

**Claude Code shows `API Usage Billing` instead of local model**

Your Ollama env vars aren't active. Run:
```bash
source <(claude-controller --export)
```

**`litellm.UnsupportedParamsError` for Gemini**

The `drop_params: true` is missing from your LiteLLM config. Add it:
```bash
echo "
litellm_settings:
  drop_params: true" >> ~/.config/litellm/config.yaml
sudo lsof -ti :11435 | xargs kill -9 2>/dev/null || true
claude-controller
```

**Check LiteLLM logs**
```bash
cat ~/.cache/agentrun/litellm.log
```

---

## When to use which backend

| Situation | Backend |
|-----------|---------|
| Privacy, offline, free | Ollama |
| Best Claude quality (Pro/Max plan) | Anthropic |
| GPT-4o specifically | OpenAI via LiteLLM |
| Gemini 2.0 Flash (fast + cheap) | Gemini via LiteLLM |
| Gemini 2.5 Pro (strong reasoning) | Gemini via LiteLLM |
