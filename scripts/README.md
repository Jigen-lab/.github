# scripts/

Helper scripts for the Jigen GitHub organization.

## bootstrap-repo.sh

Creates a new repository under `Jigen-lab` with sensible defaults: scaffolds README/LICENSE/.gitignore/dependabot, grants team access, enables Private Vulnerability Reporting, and applies the standard label set.

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

# Preview what would happen, change nothing
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
6. Removes GitHub default labels and applies the set from `labels.json`

### What it does NOT do (already org-wide)

- 2FA enforcement, default permissions, Dependabot/secret scanning defaults — applied at org level
- Branch ruleset (signed commits, PR required, no force push) — applied at org level via `default-branch-protection`
- Allowed Actions whitelist — applied at org level

## labels.json

The standard label set applied to every new repo. Edit here, then re-run on existing repos to sync.

Categories:
- `type:` — what kind of work (bug, feature, docs, chore, refactor, test, security, breaking)
- `priority:` — P0 (critical) → P3 (cosmetic)
- `status:` — needs-triage, blocked, in-progress, ready, needs-info
- `area:` — backend, frontend, infra, ci, dependencies
- Generic: good first issue, help wanted, duplicate, wontfix, invalid, question

## dependabot-templates/

One YAML file per supported language. Used by `bootstrap-repo.sh` and as a reference if you need to manually add a dependabot config to an existing repo.
