# Orchestrator Enterprise Enforcement — Global Hooks

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every `git push` from this machine runs `orchestrator-enterprise scan` — blocked on errors, allowed on warnings/info. Enforced via both git pre-push hook (catches manual pushes) and Claude Code PreToolUse hook (catches AI-driven pushes).

**Architecture:** Two independent enforcement layers. The git hook catches `git push` from any shell. The Claude Code hook catches push attempts via the Bash tool before the command runs. Both use the same `--fail-on error` exit code — no JSON parsing, no python dependency.

**Tech Stack:** Bash (git hook), Node.js (Claude Code hook script), Claude Code settings.json

---

## Current State

- `~/.git-hooks/pre-push` exists with orchestrator logic but uses fragile JSON+python3 parsing
- `core.hooksPath` already set to `~/.git-hooks/`
- Claude Code has no PreToolUse hooks — only SessionStart and UserPromptSubmit
- `orchestrator-enterprise` v4.0.0 installed at `~/.local/bin/orchestrator-enterprise`
- `--fail-on error` exit code: 0 = no errors, 1 = errors found. Clean, no parsing needed.
- 33 repos in ~/git/, ~30 have .github/workflows/

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `~/.git-hooks/pre-push` | Rewrite | Simpler, no python dep, --fail-on error |
| `~/.claude/hooks/orchestrator-pre-push.sh` | Create | Script for Claude Code hook |
| `~/.claude/settings.json` | Modify | Add PreToolUse hook entry |

---

### Task 1: Rewrite global git pre-push hook

**Files:**
- Modify: `~/.git-hooks/pre-push`

- [ ] **Step 1: Back up existing hook**

```bash
cp ~/.git-hooks/pre-push ~/.git-hooks/pre-push.bak.2026-04-14
```

- [ ] **Step 2: Write new pre-push hook**

Replace `~/.git-hooks/pre-push` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────
# Global pre-push hook: Orchestrator Enterprise governance
# + Git LFS
# ─────────────────────────────────────────────────────────

# ── Git LFS ──────────────────────────────────────────────
if command -v git-lfs >/dev/null 2>&1; then
  git lfs pre-push "$@"
fi

# ── Skip gate ────────────────────────────────────────────
if [ "${SKIP_ENFORCE:-0}" = "1" ]; then
  exit 0
fi

# ── Find enforcer binary ────────────────────────────────
ENFORCER=""
for candidate in \
  "$HOME/.local/bin/orchestrator-enterprise" \
  "/opt/haskell/cabal/bin/orchestrator-enterprise" \
  "$(command -v orchestrator-enterprise 2>/dev/null || true)"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    ENFORCER="$candidate"
    break
  fi
done

if [ -z "$ENFORCER" ]; then
  echo "⚠ orchestrator-enterprise not found — governance check skipped" >&2
  exit 0
fi

# ── Find repo root + workflows ──────────────────────────
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/.github/workflows" ]; then
  exit 0
fi

echo "╭──────────────────────────────────────────────╮"
echo "│  Orchestrator Enterprise — pre-push scan     │"
echo "╰──────────────────────────────────────────────╯"

# ── Run scan with --fail-on error ────────────────────────
# Exit code: 0 = no errors (warnings OK), 1 = errors found
if "$ENFORCER" scan "$REPO_ROOT" --fail-on error; then
  echo "  ✓ Governance check passed — push allowed"
  exit 0
else
  echo ""
  echo "  ✗ BLOCKED: orchestrator-enterprise found error-level violations"
  echo "  Run: orchestrator-enterprise scan $REPO_ROOT"
  echo "  Override: SKIP_ENFORCE=1 git push"
  exit 1
fi
```

- [ ] **Step 3: Make executable and verify syntax**

```bash
chmod +x ~/.git-hooks/pre-push
bash -n ~/.git-hooks/pre-push
```

- [ ] **Step 4: Verify it works on a repo with errors**

```bash
cd ~/git/Haskell-Orchestrator
# Simulate pre-push (hook receives remote name + URL as args)
~/.git-hooks/pre-push origin https://github.com/test/test < /dev/null
echo "Exit: $?"
# Expected: exit 1 (SEC-002 error in release-haskell.yml)
```

- [ ] **Step 5: Verify it works on a repo with only warnings**

```bash
cd ~/git/aihelp
~/.git-hooks/pre-push origin https://github.com/test/test < /dev/null
echo "Exit: $?"
# Expected: exit 0 (warnings only, no errors)
```

---

### Task 2: Create Claude Code hook script

**Files:**
- Create: `~/.claude/hooks/orchestrator-pre-push.sh`

- [ ] **Step 1: Write the hook script**

The Claude Code PreToolUse hook receives JSON on stdin with the tool name and input.
For Bash tool, `input.command` contains the shell command. We check if it contains `git push`.

```bash
#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────
# Claude Code PreToolUse hook: orchestrator-enterprise gate
# Intercepts Bash commands containing "git push"
# Returns JSON: {"decision":"block","reason":"..."} or nothing (allow)
# ─────────────────────────────────────────────────────────

# Read hook input from stdin
INPUT="$(cat)"

# Only act on Bash tool
TOOL_NAME="$(echo "$INPUT" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('tool_name',''))" 2>/dev/null || true)"
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

# Extract the command
COMMAND="$(echo "$INPUT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)"

# Check if command contains git push (not just "push" — be specific)
if ! echo "$COMMAND" | grep -qE '\bgit\s+push\b'; then
  exit 0
fi

# ── Find enforcer ────────────────────────────────────────
ENFORCER=""
for candidate in \
  "$HOME/.local/bin/orchestrator-enterprise" \
  "/opt/haskell/cabal/bin/orchestrator-enterprise" \
  "$(command -v orchestrator-enterprise 2>/dev/null || true)"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    ENFORCER="$candidate"
    break
  fi
done

if [ -z "$ENFORCER" ]; then
  # Can't enforce — allow but warn
  echo '{"decision":"warn","message":"orchestrator-enterprise not found — governance check skipped"}'
  exit 0
fi

# ── Find repo root ───────────────────────────────────────
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/.github/workflows" ]; then
  # No workflows — nothing to scan
  exit 0
fi

# ── Run scan ─────────────────────────────────────────────
if "$ENFORCER" scan "$REPO_ROOT" --fail-on error >/dev/null 2>&1; then
  # Clean — allow the push
  exit 0
else
  echo "{\"decision\":\"block\",\"reason\":\"orchestrator-enterprise found error-level violations in $REPO_ROOT workflows. Run: orchestrator-enterprise scan $REPO_ROOT\"}"
  exit 0
fi
```

- [ ] **Step 2: Make executable**

```bash
chmod +x ~/.claude/hooks/orchestrator-pre-push.sh
bash -n ~/.claude/hooks/orchestrator-pre-push.sh
```

---

### Task 3: Add Claude Code PreToolUse hook to settings.json

**Files:**
- Modify: `~/.claude/settings.json`

- [ ] **Step 1: Add PreToolUse hook entry**

Add to the `hooks` object in settings.json:

```json
"PreToolUse": [
  {
    "matcher": "Bash",
    "hooks": [
      {
        "type": "command",
        "command": "bash /home/jalsarraf/.claude/hooks/orchestrator-pre-push.sh",
        "timeout": 30,
        "statusMessage": "Running orchestrator governance scan..."
      }
    ]
  }
]
```

---

### Task 4: End-to-end testing

- [ ] **Step 1: Test git hook blocks push on repo with errors**

```bash
cd ~/git/Haskell-Orchestrator
~/.git-hooks/pre-push origin https://github.com/test/test < /dev/null
# Expected: exit 1
```

- [ ] **Step 2: Test git hook allows push on repo with warnings only**

```bash
cd ~/git/aihelp
~/.git-hooks/pre-push origin https://github.com/test/test < /dev/null
# Expected: exit 0
```

- [ ] **Step 3: Test git hook skips repos without workflows**

```bash
cd ~/git/claudesource  # no workflows
~/.git-hooks/pre-push origin https://github.com/test/test < /dev/null
# Expected: exit 0, silent
```

- [ ] **Step 4: Test Claude Code hook blocks push**

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' | \
  bash ~/.claude/hooks/orchestrator-pre-push.sh
# Expected: {"decision":"block","reason":"..."}  (when run from Haskell-Orchestrator)
```

- [ ] **Step 5: Test Claude Code hook allows non-push commands**

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | \
  bash ~/.claude/hooks/orchestrator-pre-push.sh
# Expected: empty output, exit 0
```

- [ ] **Step 6: Test Claude Code hook allows non-Bash tools**

```bash
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test"}}' | \
  bash ~/.claude/hooks/orchestrator-pre-push.sh
# Expected: empty output, exit 0
```
