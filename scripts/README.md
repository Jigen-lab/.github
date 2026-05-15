# scripts/

Helper scripts and configuration for the Jigen GitHub organization.

## Issue Types vs Labels — division of concerns

We use **both**, but for different purposes:

| | Issue Types | Labels |
|---|---|---|
| **Scope** | Org-wide (one set, applies to all repos) | Per-repo (synced via `sync-labels.sh`) |
| **Cardinality** | Exactly **1** per issue | Many per issue |
| **Question they answer** | "What kind of work is this?" | "What attributes does it have?" |
| **Examples** | Bug, Feature, Task, Improvement, Documentation | priority, status, area, impact |

Configured Issue Types (managed in GitHub UI / API at the org level):
- **Bug** — unexpected problem or behavior
- **Feature** — request, idea, or new functionality
- **Task** — specific piece of work
- **Improvement** — enhancement to existing functionality
- **Documentation** — docs work

Configured label namespaces (in `labels.json`):
- `priority: P0/P1/P2/P3` — severity
- `status: needs-triage/blocked/in-progress/ready/needs-info/wontfix/duplicate/invalid` — workflow state
- `area: backend/frontend/infra/ci/dependencies/security` — codebase area
- `impact: breaking/performance` — special impact warnings
- Generic: `good first issue`, `help wanted`, `question`

---

## bootstrap-repo.sh

Creates a new repository under `Jigen-lab` with sensible defaults.

### Prerequisites

- `gh` CLI authenticated (`gh auth login`) with scopes: `admin:org`, `repo`, `delete_repo`
- `git`, `jq`, `curl` installed
- GPG signing configured (`git config --global commit.gpgsign true`)

### Usage

```bash
# Private repo (default), TypeScript
./scripts/bootstrap-repo.sh api --lang ts --description "Public REST API"

# Public Python repo
./scripts/bootstrap-repo.sh worker --lang py --description "Background job processor" --public

# C# repo without granting team access (you'll add manually)
./scripts/bootstrap-repo.sh services --lang cs --no-team

# Multi-language monorepo
./scripts/bootstrap-repo.sh platform --lang mix --description "Main platform monorepo"

# Preview, change nothing
./scripts/bootstrap-repo.sh demo --lang ts --dry-run
```

### Supported languages (`--lang`)

| Value | Stack | .gitignore | Dependabot ecosystems |
|---|---|---|---|
| `ts` | TypeScript / Node.js | `Node.gitignore` | github-actions, npm |
| `py` | Python | `Python.gitignore` | github-actions, pip |
| `cs` | C# / .NET | `VisualStudio.gitignore` | github-actions, nuget |
| `mix` | Multiple | generic stub | github-actions only (uncomment others) |

### What it does

1. Creates `Jigen-lab/<name>` (private by default)
2. Scaffolds: `README.md`, `LICENSE` (MIT), `.gitignore`, `.github/dependabot.yml`
3. Initial GPG-signed commit and push to `main`
4. Grants `@Jigen-lab/engineering` write access, `@Jigen-lab/security` read access
5. Enables Private Vulnerability Reporting
6. Calls `sync-labels.sh` to apply the standard label set

---

## sync-labels.sh

Idempotent label synchronization across one or all repos.

### Usage

```bash
# Sync labels.json to ALL repos
./scripts/sync-labels.sh --all

# Sync to specific repo(s)
./scripts/sync-labels.sh --repo api --repo web

# Also delete labels NOT in labels.json (cleanup mode)
./scripts/sync-labels.sh --all --delete-extra

# Preview changes — no modifications
./scripts/sync-labels.sh --all --dry-run
```

### Behavior (idempotent)

- Label in `labels.json`, NOT in repo → **CREATE**
- Label in `labels.json`, in repo, color/description differ → **UPDATE**
- Label in `labels.json`, in repo, identical → skip
- Label in repo, NOT in `labels.json` → kept (use `--delete-extra` to remove)

Run after editing `labels.json` to roll out changes everywhere:
```bash
./scripts/sync-labels.sh --all --delete-extra
```

---

## labels.json

The single source of truth for labels across all repos.

To add/edit a label, modify this file then run `sync-labels.sh --all --delete-extra`.

GitHub default labels (`bug`, `enhancement`, `wontfix`, etc.) are intentionally NOT in `labels.json` because they're replaced by our `status: *` and Issue Types. They get removed by `--delete-extra`.

---

## bootstrap-claude-code.sh

Interactive installer that sets up Claude Code on a Jigen developer laptop following the canonical guide in [`Jigen-lab/playbook/tooling/claude-code-setup.md`](https://github.com/Jigen-lab/playbook/blob/main/tooling/claude-code-setup.md).

### Prerequisites

- `claude` CLI on PATH (install: `curl -fsSL https://claude.ai/install.sh | sh`)
- `jq`, `curl` installed

### Usage

```bash
# Full Jigen baseline, interactive prompts (canonical first run)
curl -fsSL https://raw.githubusercontent.com/Jigen-lab/.github/main/scripts/bootstrap-claude-code.sh | bash

# Or run a checked-out copy
./scripts/bootstrap-claude-code.sh

# Skip per-section confirmation (apply everything)
./scripts/bootstrap-claude-code.sh --exact

# Preview without modifying anything
./scripts/bootstrap-claude-code.sh --dry-run

# Settings + CLAUDE.md only — skip the marketplace + plugin install
./scripts/bootstrap-claude-code.sh --skip-plugins --skip-mcp
```

### What it does (idempotent)

1. **Preflight** — verifies `claude`, `jq`, `curl` on PATH
2. **claude-switch** — detects (or offers to install) [`SaschaHeyer/claude-switch`](https://github.com/SaschaHeyer/claude-switch) for multi-account profiles. Configures the **currently-active** profile; for other profiles, switch and re-run.
3. **About-me placeholders** — prompts for `Name`, `Role`, `Background`, `Strong in`, `Still learning`. These are baked into `~/.claude/CLAUDE.md` (no `[Your Name]` placeholders left in the final file).
4. **Backup** — copies existing `~/.claude` to `~/.claude.backup.<timestamp>` before any change (skip with `--no-backup`)
5. **`settings.json`** — `jq`-merges the mandatory keys (attribution suppression, `alwaysThinkingEnabled`, `effortLevel: high`, `autoCompactWindow: 850000`, `autoUpdatesChannel: latest`, `statusLine`, two `PostToolUse` hooks for `ruff` and JSON validation) into the existing settings, preserving user-set keys. Optionally also sets `permissions.defaultMode: bypassPermissions` + the canonical 8-command ask-list.
6. **imperStatusLine** — downloads from [`imperugo/imperStatusLine`](https://github.com/imperugo/imperStatusLine) into `~/.claude/imperStatusLine.sh`
7. **`~/.claude/CLAUDE.md`** — writes the Jigen baseline (Kopadze + Karpathy patterns + Jigen Git/GitHub conventions) with collected placeholders substituted
8. **Marketplaces** — adds 8 marketplaces via `claude plugin marketplace add` (the 9th, `claude-plugins-official`, is auto-distributed by Anthropic)
9. **Plugin baseline** — installs 22 global plugins via `claude plugin install` (per-stack ones like `jigen-node` / `terraform-skill` / `claude-seo` / `wiki` / `write-a-skill` stay per-repo)
10. **Context7 MCP** — `claude mcp add context7 --scope=user -- npx -y @upstash/context7-mcp@latest`

The script always asks before overwriting existing files (`CLAUDE.md`, `imperStatusLine.sh`). `settings.json` is always merged, never replaced.

### Flags

| Flag | Effect |
|---|---|
| `--exact` | No per-step confirmation — run everything |
| `--selective` | Ask before every section (default) |
| `--dry-run` | Print actions, change nothing |
| `--skip-plugins` | Skip marketplace + plugin install |
| `--skip-mcp` | Skip Context7 MCP setup |
| `--no-backup` | Do not back up `~/.claude` first (not recommended) |
| `-h`, `--help` | Print usage and exit |

---

## dependabot-templates/

One YAML file per supported language. Used by `bootstrap-repo.sh` and as a manual reference.
