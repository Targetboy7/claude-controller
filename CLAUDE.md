# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`claude-controller` is a single Bash script that lets a user switch Claude Code between
different AI backends (Ollama, Anthropic, OpenAI via LiteLLM, Gemini via LiteLLM) and then
launches Claude Code with the right environment variables set. There is no build system,
package manager, or test suite — the entire application is `claude-controller.sh`.

## Development commands

There is no build, lint, or test tooling configured in this repo. Useful manual checks when
editing `claude-controller.sh`:

```bash
bash -n claude-controller.sh        # syntax check
shellcheck claude-controller.sh     # lint, if shellcheck is installed locally
./claude-controller.sh --help       # sanity-check the CLI still parses args correctly
./claude-controller.sh --status     # inspect persisted state without launching anything
./claude-controller.sh --list       # verify backend table renders correctly
```

There are no automated tests. Verify behavioral changes by running the relevant subcommand
(`--status`, `--export`, `--list`, `--stop-litellm`, `--setup-litellm`, or the default
interactive flow) and checking output and the files under `~/.cache/agentrun/` and
`~/.config/claude-controller/`.

## Architecture

The script (`claude-controller.sh`) is organized into clearly delimited sections (look for the
`# ── Section ───` banners). The flow for the default interactive invocation is:

```
mode_interactive
  → print_header            (shows current state + Ollama/LiteLLM status)
  → pick_backend             (reads BACKENDS array)
  → pick_ollama_model / pick_api_model   (reads the matching *_REGISTRY array)
  → apply_ollama / apply_anthropic / apply_openai / apply_gemini
  → launch_claude             (sources the env file, then execs ollama/claude)
```

Key data structures and conventions:

- **Backend/model tables are pipe-delimited string arrays**, parsed with
  `IFS='|' read -r ...`. `BACKENDS` holds `id|label|description|key_var` records;
  `OLLAMA_REGISTRY`, `ANTHROPIC_REGISTRY`, `OPENAI_REGISTRY`, `GEMINI_REGISTRY` hold the
  model lists for each backend (format differs slightly per registry — Ollama is
  `model|best_for`, the API registries are `model|display_name|context|cost`). When adding or
  changing models/backends, edit these arrays and keep the field order consistent with how
  they're destructured elsewhere in the script.
- **Each backend has a matching `apply_<backend>` function** that: stops any running LiteLLM
  proxy, persists the selection via `save_state`, and writes the resulting `export ...` lines
  to the env file via `write_env`. `launch_claude` later sources that file and `exec`s either
  `ollama launch claude --model $CLAUDE_MODEL` (Ollama) or `claude --model $CLAUDE_MODEL`
  (everything else).
- **LiteLLM is the translation layer for OpenAI/Gemini.** `start_litellm`/`stop_litellm` manage
  a local LiteLLM proxy on port 11435 (PID tracked in `~/.cache/agentrun/litellm.pid`, logs in
  `~/.cache/agentrun/litellm.log`). Claude Code only speaks the Anthropic API format, so
  `ANTHROPIC_BASE_URL` is pointed at the local proxy and `drop_params: true` must remain set in
  `~/.config/litellm/config.yaml` (written by `--setup-litellm`) so LiteLLM silently drops
  Anthropic-specific params that OpenAI/Gemini don't understand.
- **API keys** are managed by `load_key`/`prompt_key`/`key_status`, backed by
  `~/.config/claude-controller/keys.env` (chmod 600), falling back to existing environment
  variables. The Anthropic backend is special-cased: if no `ANTHROPIC_API_KEY` is stored, it
  unsets the Ollama/LiteLLM overrides and relies on the user's existing `claude login` session
  instead of prompting for a key.
- **Persistent state lives outside the repo**, under `~/.cache/agentrun/` (`backend_state.json`
  for the last backend/model, `model_env.sh` for the exported env vars) and
  `~/.config/claude-controller/keys.env` / `~/.config/litellm/config.yaml`. `save_state`/
  `get_state` use Python's `json` module with a manual-string fallback if `python3` isn't
  available.
- **CLI dispatch** is a single `case "${1:-}"` at the bottom of the script
  (`--status`, `--export`, `--stop-litellm`, `--setup-litellm`, `--list`, `--help`, default →
  `mode_interactive`). When adding a new flag, add a case here rather than introducing a
  separate arg-parsing mechanism.

See `README.md` for the full backend comparison table, installation steps, the LiteLLM config
format, and the troubleshooting guide (port conflicts, missing `drop_params`, stale Ollama env
vars, etc.) — read it before changing setup/install-related behavior since it documents
user-facing assumptions (PATH setup, systemd Ollama service, file locations) that the script
relies on.
