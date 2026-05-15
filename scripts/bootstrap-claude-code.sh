#!/usr/bin/env bash
#
# bootstrap-claude-code.sh — set up Claude Code on a Jigen developer laptop.
#
# Companion to playbook/tooling/claude-code-setup.md — implements the full
# manual sequence interactively, with idempotent re-runs and a backup of the
# existing ~/.claude before any change.
#
# Usage:
#   ./bootstrap-claude-code.sh [options]
#
# Options:
#   --exact         Run the full Jigen baseline without per-step confirmation
#   --selective     Ask before every section (default)
#   --dry-run       Print actions without executing
#   --skip-plugins  Skip marketplace + plugin install (settings + CLAUDE.md only)
#   --skip-mcp      Skip Context7 MCP setup
#   --no-backup     Do not back up ~/.claude before changes (NOT recommended)
#   -h, --help      Show this help
#
# What it does (in order):
#   0. Preflight — verifies claude / jq / curl are installed
#   1. Optional claude-switch detection / install + profile guidance
#   2. Collects About-me placeholders (name, role, background, strong-in, learning)
#   3. Backs up ~/.claude → ~/.claude.backup.<timestamp>
#   4. Merges mandatory keys into ~/.claude/settings.json (preserves user keys)
#      Configures: attribution suppression, alwaysThinking, effortLevel high,
#      autoCompactWindow 850000, autoUpdatesChannel latest, statusLine,
#      two PostToolUse hooks (ruff fix on .py, JSON validate on .json)
#   5. Downloads imperStatusLine into ~/.claude/imperStatusLine.sh
#   6. Writes ~/.claude/CLAUDE.md from the Jigen baseline with placeholders
#      substituted from step 2
#   7. Adds 8 marketplaces via `claude plugin marketplace add`
#   8. Installs 22 baseline plugins via `claude plugin install`
#   9. Adds Context7 MCP server (user scope) via `claude mcp add`
#  10. Prints a summary + next-step guidance
#
# Idempotent: re-run after edits. Sections detect existing state and ask
# before overwriting.
#
# Reference: Jigen-lab/playbook/tooling/claude-code-setup.md (full prose)
#

set -euo pipefail

# ---------- Constants ----------
SCRIPT_VERSION="0.1.0"
BOOTSTRAP_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
IMPER_STATUSLINE_URL="https://raw.githubusercontent.com/imperugo/imperStatusLine/main/imperStatusLine.sh"

# Marketplaces to register: "folder_name source_url"
# (claude-plugins-official is auto-distributed by Anthropic; no manual add)
MARKETPLACES=(
  "anthropic-agent-skills https://github.com/anthropics/skills"
  "claude-code-plugins https://github.com/anthropics/claude-code"
  "claude-code-workflows https://github.com/wshobson/agents"
  "agricidaniel-seo https://github.com/AgriciDaniel/claude-seo"
  "antonbabenko https://github.com/antonbabenko/terraform-skill"
  "thedotmack https://github.com/thedotmack/claude-mem"
  "mattpocock https://github.com/mattpocock/skills"
  "jigen-ai-tools-marketplace https://github.com/Jigen-lab/ai-tools-marketplace"
)

# Baseline plugins to install globally (user scope).
# Per-stack plugins (jigen-node, jigen-python, terraform-skill, claude-seo,
# wiki, mattpocock/write-a-skill) are intentionally NOT installed here —
# they belong per-repo to keep sessions lean.
BASELINE_PLUGINS=(
  # claude-plugins-official (13)
  "claude-code-setup@claude-plugins-official"
  "claude-md-management@claude-plugins-official"
  "code-review@claude-plugins-official"
  "code-simplifier@claude-plugins-official"
  "csharp-lsp@claude-plugins-official"
  "explanatory-output-style@claude-plugins-official"
  "feature-dev@claude-plugins-official"
  "frontend-design@claude-plugins-official"
  "pr-review-toolkit@claude-plugins-official"
  "pyright-lsp@claude-plugins-official"
  "ralph-wiggum@claude-plugins-official"
  "security-guidance@claude-plugins-official"
  "typescript-lsp@claude-plugins-official"
  # jigen-ai-tools-marketplace (3 — jigen-node/jigen-python live per-repo)
  "jigen-essentials@jigen-ai-tools-marketplace"
  "jigen-issue@jigen-ai-tools-marketplace"
  "jigen-security@jigen-ai-tools-marketplace"
  # claude-code-workflows (4)
  "backend-api-security@claude-code-workflows"
  "dependency-management@claude-code-workflows"
  "frontend-mobile-security@claude-code-workflows"
  "security-scanning@claude-code-workflows"
  # anthropic-agent-skills (1)
  "document-skills@anthropic-agent-skills"
  # thedotmack (1)
  "claude-mem@thedotmack"
)

# Argparse defaults
DRY_RUN="false"
SKIP_PLUGINS="false"
SKIP_MCP="false"
DO_BACKUP="true"
MODE="ask"  # "ask" | "exact" | "selective"

# Placeholder collection (populated in collect_placeholders)
USER_NAME=""
USER_ROLE=""
USER_BACKGROUND=""
USER_STRONG=""
USER_LEARNING=""

# ---------- Helpers ----------

die()  { echo "ERROR: $*" >&2; exit 1; }
log()  { echo "  → $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*" >&2; }
heading() { echo ""; echo "── $* ──────────────────────"; }

print_usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//; s/^#$//'
}

# ask "prompt" "default" → echoes the answer (default if empty input)
ask() {
  local prompt="$1"
  local default="${2:-}"
  local answer
  if [[ -n "$default" ]]; then
    read -rp "  $prompt [$default]: " answer
    echo "${answer:-$default}"
  else
    read -rp "  $prompt: " answer
    echo "$answer"
  fi
}

# confirm "prompt" "default Y/N" → exit 0 (yes) or 1 (no)
confirm() {
  local prompt="$1"
  local default="${2:-Y}"
  local hint
  if [[ "$default" == "Y" ]]; then hint="[Y/n]"; else hint="[y/N]"; fi
  local response
  read -rp "  $prompt $hint: " response
  response="${response:-$default}"
  [[ "$response" =~ ^[Yy]$ ]]
}

# in_exact_mode → returns 0 if we should run without per-step prompts
in_exact_mode() { [[ "$MODE" == "exact" ]]; }

# step "prompt"  → returns 0 (run) or 1 (skip)
# Always runs in exact mode; asks in selective mode.
step() {
  local prompt="$1"
  in_exact_mode && return 0
  confirm "$prompt"
}

# ---------- Argparse ----------

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)       DRY_RUN="true"; shift ;;
      --skip-plugins)  SKIP_PLUGINS="true"; shift ;;
      --skip-mcp)      SKIP_MCP="true"; shift ;;
      --no-backup)     DO_BACKUP="false"; shift ;;
      --exact)         MODE="exact"; shift ;;
      --selective)     MODE="selective"; shift ;;
      -h|--help)       print_usage; exit 0 ;;
      *) die "Unknown option: $1 (try --help)" ;;
    esac
  done
}

# ---------- 0. Preflight ----------

preflight() {
  heading "0. Preflight"
  command -v claude >/dev/null 2>&1 || \
    die "Claude Code CLI not on PATH. Install: curl -fsSL https://claude.ai/install.sh | sh"
  command -v jq >/dev/null 2>&1 || \
    die "jq required. macOS: 'brew install jq'  Linux: 'apt-get install jq'"
  command -v curl >/dev/null 2>&1 || die "curl required"

  log "claude: $(claude --version)"
  log "jq: $(jq --version)"
  ok "Prerequisites OK"

  if [[ "$DRY_RUN" == "true" ]]; then
    warn "DRY-RUN mode — no files will be modified"
  fi
}

# ---------- 1. claude-switch ----------

handle_claude_switch() {
  heading "1. Multi-account profiles (claude-switch)"
  if command -v claude-switch >/dev/null 2>&1; then
    log "claude-switch detected"
    if claude-switch list 2>/dev/null; then
      :
    else
      log "(no profiles yet)"
    fi
    warn "claude-switch swaps ~/.claude per profile."
    warn "This script configures the CURRENTLY-ACTIVE profile only."
    warn "To configure other profiles: 'claude-switch <name>' to switch, then re-run this script."
    return
  fi

  log "claude-switch not detected"
  if ! step "Install claude-switch for multiple Claude accounts?"; then
    log "Skipped"; return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "(dry-run) would install gum + claude-switch"
    return
  fi

  if ! command -v gum >/dev/null 2>&1; then
    log "Installing gum (claude-switch dependency)"
    if command -v brew >/dev/null 2>&1; then
      brew install gum
    else
      warn "gum not available; install manually then re-run"
      return
    fi
  fi

  curl -fsSL https://raw.githubusercontent.com/SaschaHeyer/claude-switch/main/install.sh | sh
  ok "claude-switch installed (run 'claude-switch create <name>' to create profiles)"
}

# ---------- 2. Collect placeholders ----------

collect_placeholders() {
  heading "2. About me — populates ~/.claude/CLAUDE.md"
  echo "  These five values shape every response Claude gives you across all projects."
  echo ""
  USER_NAME="$(ask 'Name' "$(git config user.name 2>/dev/null || echo '')")"
  USER_ROLE="$(ask 'Role (engineer / writer / founder / marketer / researcher / other)' 'engineer')"
  USER_BACKGROUND="$(ask 'Background (1 short sentence)')"
  USER_STRONG="$(ask 'Strong in (comma-separated topics — Claude skips basics here)')"
  USER_LEARNING="$(ask 'Still learning (comma-separated topics — Claude adds context here)')"

  [[ -n "$USER_NAME" ]] || die "Name is required"
  [[ -n "$USER_ROLE" ]] || die "Role is required"
  ok "Placeholders collected"
}

# ---------- 3. Backup ----------

backup_dotclaude() {
  heading "3. Backup ~/.claude"
  if [[ "$DO_BACKUP" != "true" ]]; then
    warn "Backup skipped (--no-backup)"; return
  fi
  if [[ ! -d "$HOME/.claude" ]]; then
    log "No ~/.claude yet, nothing to back up"; return
  fi
  local backup
  backup="$HOME/.claude.backup.$(date +%Y%m%d-%H%M%S)"
  log "Copying ~/.claude → $backup"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "(dry-run) would create $backup"; return
  fi
  cp -R "$HOME/.claude" "$backup"
  ok "Backup at $backup"
}

# ---------- 4. settings.json merge ----------

merge_settings() {
  heading "4. ~/.claude/settings.json (merge mandatory keys)"

  if ! step "Apply mandatory settings (attribution, thinking, effort, hooks, status line)?"; then
    log "Skipped"; return
  fi

  mkdir -p "$HOME/.claude"
  local target="$HOME/.claude/settings.json"
  local existing="{}"
  [[ -f "$target" ]] && existing="$(cat "$target")"

  # Patch JSON (heredoc — no escaping gymnastics)
  local patch
  patch="$(cat <<'JSON'
{
  "attribution": {
    "commit": "",
    "pr": ""
  },
  "alwaysThinkingEnabled": true,
  "effortLevel": "high",
  "autoCompactWindow": 850000,
  "autoUpdatesChannel": "latest",
  "statusLine": {
    "type": "command",
    "command": "bash $HOME/.claude/imperStatusLine.sh",
    "padding": 0
  },
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path' | xargs -I {} sh -c 'case \"{}\" in *.py) ruff check --fix \"{}\" ;; esac'",
            "timeout": 30
          }
        ]
      },
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path' | xargs -I {} sh -c 'case \"{}\" in *.json) python3 -m json.tool \"{}\" > /dev/null || (echo \"Invalid JSON in {}\" >&2; exit 2) ;; esac'",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
JSON
  )"

  # Optional: permissions allowlist pattern
  if step "Also configure 'bypassPermissions' mode + ask-list for dangerous commands?"; then
    local perm_patch
    perm_patch="$(cat <<'JSON'
{
  "permissions": {
    "defaultMode": "bypassPermissions",
    "ask": [
      "Bash(rm -rf *)",
      "Bash(sudo *)",
      "Bash(chmod 777 *)",
      "Bash(mkfs *)",
      "Bash(dd *)",
      "Bash(git push --force *)",
      "Bash(git reset --hard *)",
      "Bash(*prisma reset*)"
    ]
  }
}
JSON
    )"
    patch="$(jq -s '.[0] * .[1]' <(echo "$patch") <(echo "$perm_patch"))"
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "(dry-run) would merge into settings.json:"
    echo "$patch" | jq . >&2
    return
  fi

  # Deep merge existing + patch (right wins for conflicts)
  echo "$existing" | jq --argjson p "$patch" '. * $p' > "$target.tmp"
  mv "$target.tmp" "$target"
  ok "settings.json updated"
}

# ---------- 5. imperStatusLine ----------

install_statusline() {
  heading "5. imperStatusLine"

  if ! step "Install imperStatusLine (~/.claude/imperStatusLine.sh)?"; then
    log "Skipped"; return
  fi

  local target="$HOME/.claude/imperStatusLine.sh"
  if [[ -f "$target" ]] && ! confirm "  Re-download (overwrite existing)?" "N"; then
    log "Keeping existing status line"; return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "(dry-run) would curl $IMPER_STATUSLINE_URL → $target"; return
  fi

  mkdir -p "$HOME/.claude"
  curl -fsSL "$IMPER_STATUSLINE_URL" -o "$target"
  chmod +x "$target"
  ok "imperStatusLine installed"
}

# ---------- 6. CLAUDE.md ----------

write_claude_md() {
  heading "6. ~/.claude/CLAUDE.md (global baseline)"

  if ! step "Write the Jigen-aligned global CLAUDE.md with your placeholders?"; then
    log "Skipped"; return
  fi

  local target="$HOME/.claude/CLAUDE.md"
  if [[ -f "$target" ]] && ! confirm "  Overwrite existing ~/.claude/CLAUDE.md?" "N"; then
    log "Keeping existing CLAUDE.md (your placeholders were NOT applied)"; return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "(dry-run) would write CLAUDE.md (name=$USER_NAME, role=$USER_ROLE)"
    return
  fi

  mkdir -p "$HOME/.claude"
  cat > "$target" <<EOF_CLAUDE_MD
# Global CLAUDE.md

Personal preferences applied to all projects.

## How you talk to me

- Never open responses with filler phrases like "Great question!", "Of course!", "Certainly!", "Absolutely!". Start every response with the actual answer — no preamble, no acknowledgment of the question.
- Match response length to task complexity. Simple questions get direct, short answers; complex tasks get full, detailed responses. Never pad responses with restatements of the question or closing sentences that recap what was said.

## Honesty about uncertainty

If you are uncertain about any fact, statistic, date, quote, or piece of information, say so. "I'm not certain about this" is always better than presenting a guess as a fact. Never fill gaps in your knowledge with plausible-sounding information. When in doubt, say so.

## Planning

Always plan before implementing. When the task involves multi-file refactoring, infrastructure changes, architecture decisions, or any significant alteration of content I've already created (code, docs, copy), present 2-3 options before acting, then wait for explicit approval before making changes. "I think this would be better" is not permission to change something — describe exactly what you're about to change and why, and wait for confirmation.

## Scope discipline

- Only change what I specifically asked you to change. Do not rewrite, rephrase, restructure, or "improve" anything I did not ask about.
- If you notice something worth fixing elsewhere, mention it as a note — do not touch it unless I explicitly ask.
- Before any destructive action (deleting files, overwriting existing code, dropping database records, force-pushing, removing dependencies, etc.), describe what will be affected and wait for explicit confirmation.

## Hard stops — actions that never happen without explicit permission

Never send, post, publish, share, schedule, deploy, run migrations, or execute external API calls on my behalf without explicit confirmation in the current message. This includes:
- Emails, social posts, calendar invites, document shares
- Deploys or pushes to any environment (staging, production, etc.)
- Database schema changes / migrations
- Any command with irreversible external side effects

"You mentioned wanting to do this earlier" is not confirmation. I must say yes in the current message.

## After completing a task

End with a brief status update (not a recap). Two formats — use the one that matches the task type:

**For coding tasks:**
- **Files changed:** [list every file touched]
- **What was modified:** [one line per file]
- **Files intentionally not touched:** [if relevant]
- **Follow-up needed:** [anything requiring my attention or a decision]

**For editing or writing tasks:**
- **What was changed:** [description]
- **What was left untouched:** [if relevant]
- **What needs my attention:** [anything requiring a decision or review]

Keep it short — this is a status report, not a summary of the work.

## Git

For git operations: all commits must be GPG-signed. Never include co-author trailers in commits unless explicitly requested. When amending or force-pushing, confirm the target branch first.

## File modifications

When using sed for bulk file modifications, always verify the command worked on at least one file before proceeding. Prefer Python scripts or targeted Edit tool usage over sed for complex multi-file refactoring.

## GitHub

For accessing GitHub data (issues, PRs, repos), always use \`gh\` CLI (\`gh issue view\`, \`gh pr view\`, \`gh repo view\`, \`gh api\`). NEVER use web_fetch on GitHub URLs — most repositories are private and web_fetch will return 404.

## Writing style on GitHub

When writing PR descriptions, PR comments, issue comments, or commit messages, never include "Powered by", "Generated with", AI signatures, bot footers, or any phrasing that suggests the work was done by an AI agent rather than a human developer. Write as if you are the developer.

## The Karpathy four rules (for code work)

1. **Ask, don't assume.** If something is unclear or underspecified, ask before guessing.
2. **Simplest solution first.** Always implement the simplest thing that could work; add complexity only when justified.
3. **Don't touch unrelated code.** If a file or function is not directly part of the task, leave it alone.
4. **Flag uncertainty explicitly.** If you are not confident about an approach, say so up-front.

## Memory & continuity (per-project pattern)

When working on projects with longer time horizons, maintain these files in the project root and read them at the start of every session before doing anything else:

- **\`MEMORY.md\`** — significant decisions. For each: what was decided, why, what alternatives were rejected.
- **\`ERRORS.md\`** — failed approaches that took more than 2 attempts to fix. For each: what didn't work, what worked, note for next time. Check before suggesting an approach for tasks similar to logged ones.
- **Session-end summary** appended to \`MEMORY.md\` when I say "session end", "wrapping up", or "let's stop here". Format: Worked on / Completed / In progress / Decisions made / Next session.

## About me

- **Name:** $USER_NAME
- **Role:** $USER_ROLE
- **Background:** $USER_BACKGROUND
- **Strong in:** $USER_STRONG
- **Still learning:** $USER_LEARNING

Adjust the depth of every response to match this background. Never over-explain what I already know. Never skip context I need.

<!-- Generated by bootstrap-claude-code.sh v$SCRIPT_VERSION on $BOOTSTRAP_DATE -->
EOF_CLAUDE_MD

  ok "CLAUDE.md written ($USER_NAME, $USER_ROLE)"
}

# ---------- 7. Marketplaces ----------

add_marketplaces() {
  heading "7. Marketplaces"
  if [[ "$SKIP_PLUGINS" == "true" ]]; then warn "Skipped (--skip-plugins)"; return; fi
  if ! step "Add the 8 Jigen-baseline marketplaces?"; then log "Skipped"; return; fi

  for entry in "${MARKETPLACES[@]}"; do
    local name="${entry%% *}"
    local url="${entry#* }"
    if [[ "$DRY_RUN" == "true" ]]; then
      log "(dry-run) claude plugin marketplace add $url"; continue
    fi
    if claude plugin marketplace add "$url" >/dev/null 2>&1; then
      ok "$name"
    else
      log "$name (already present or failed silently)"
    fi
  done
  ok "Marketplaces processed"
}

# ---------- 8. Plugins ----------

install_plugins() {
  heading "8. Baseline plugins"
  if [[ "$SKIP_PLUGINS" == "true" ]]; then warn "Skipped (--skip-plugins)"; return; fi
  if ! step "Install the ${#BASELINE_PLUGINS[@]} baseline plugins?"; then log "Skipped"; return; fi

  for p in "${BASELINE_PLUGINS[@]}"; do
    if [[ "$DRY_RUN" == "true" ]]; then
      log "(dry-run) claude plugin install $p"; continue
    fi
    if claude plugin install "$p" >/dev/null 2>&1; then
      ok "$p"
    else
      log "$p (already installed or marketplace not yet synced — re-run if needed)"
    fi
  done
  ok "Plugins processed"
}

# ---------- 9. Context7 MCP ----------

add_mcp_context7() {
  heading "9. Context7 MCP (user scope)"
  if [[ "$SKIP_MCP" == "true" ]]; then warn "Skipped (--skip-mcp)"; return; fi
  if ! step "Add Context7 MCP server (first-source for library docs)?"; then log "Skipped"; return; fi

  if claude mcp list 2>/dev/null | grep -q "^context7"; then
    log "Context7 MCP already configured"; return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "(dry-run) claude mcp add context7 --scope=user -- npx -y @upstash/context7-mcp@latest"
    return
  fi

  claude mcp add context7 --scope=user -- npx -y @upstash/context7-mcp@latest >/dev/null 2>&1 \
    && ok "Context7 added" \
    || warn "Context7 add failed — check 'claude mcp list'"
}

# ---------- 10. Summary ----------

print_summary() {
  heading "Bootstrap complete"
  cat <<EOF

  Configured files:
    ~/.claude/settings.json      (merged)
    ~/.claude/CLAUDE.md          (baseline with your placeholders)
    ~/.claude/imperStatusLine.sh (status line)

  Backup:
$(ls -d "$HOME/.claude.backup."* 2>/dev/null | tail -1 | sed 's|^|    |' || echo "    (none — first run or --no-backup)")

  Verify with:
    claude doctor
    claude mcp list
    claude plugin list

  Next steps:
    - Restart any running Claude Code sessions to pick up the new config
    - Review ~/.claude/CLAUDE.md and adjust personal extras (writing voice, etc.)
    - For per-repo plugins (jigen-node, jigen-python, terraform-skill, ...)
      install them inside each repo where you actually need them:
        cd <repo>
        claude plugin install <name>@<marketplace>

  Documentation: Jigen-lab/playbook/tooling/claude-code-setup.md

EOF
}

# ---------- Main ----------

main() {
  parse_args "$@"

  if [[ "$MODE" == "ask" ]]; then
    echo ""
    echo "  Jigen Claude Code bootstrap v$SCRIPT_VERSION"
    echo ""
    if confirm "Run the full Jigen baseline (recommended)?" "Y"; then
      MODE="exact"
    else
      MODE="selective"
    fi
  fi

  preflight
  handle_claude_switch
  collect_placeholders
  backup_dotclaude
  merge_settings
  install_statusline
  write_claude_md
  add_marketplaces
  install_plugins
  add_mcp_context7
  print_summary
}

main "$@"
