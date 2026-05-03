#!/usr/bin/env bash
#
# bootstrap-repo.sh — create a new Jigen repository with sensible defaults.
#
# Usage:
#   ./scripts/bootstrap-repo.sh <name> --lang <ts|py|cs|mix> [options]
#
# Options:
#   --lang <ts|py|cs|mix>   Primary language (required)
#   --description "<text>"  Repo description
#   --public                Make repo public (default: private)
#   --no-team               Skip granting team access
#   --dry-run               Print actions without executing
#   -h, --help              Show this help
#
# What it does:
#   1. Creates the repo (private by default) under Jigen-lab
#   2. Grants @Jigen-lab/engineering write access, @Jigen-lab/security read access
#   3. Enables Private Vulnerability Reporting
#   4. Initializes a local git repo and pushes initial commit with:
#       - README.md (skeleton)
#       - .gitignore (downloaded from github/gitignore for the chosen language)
#       - .github/dependabot.yml (from scripts/dependabot-templates/)
#       - LICENSE (MIT — change in template if needed)
#   5. Creates standard labels from scripts/labels.json
#
# Org-wide defaults (already applied at org level, no action needed here):
#   - Default branch ruleset: signed commits, PR required, no force push
#   - Dependabot alerts/updates, secret scanning, push protection: on by default
#
set -euo pipefail

# ---------- Defaults ----------
ORG="Jigen-lab"
REPO_NAME=""
LANG=""
DESCRIPTION=""
VISIBILITY="private"
GRANT_TEAMS="true"
DRY_RUN="false"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/dependabot-templates"
LABELS_FILE="${SCRIPT_DIR}/labels.json"

# ---------- Helpers ----------
die()  { echo "ERROR: $*" >&2; exit 1; }
log()  { echo "  → $*"; }
step() { echo ""; echo "▶ $*"; }
run()  { if [[ "$DRY_RUN" == "true" ]]; then echo "    [dry-run] $*"; else eval "$@"; fi; }

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

gitignore_url() {
  case "$1" in
    ts)  echo "https://raw.githubusercontent.com/github/gitignore/main/Node.gitignore" ;;
    py)  echo "https://raw.githubusercontent.com/github/gitignore/main/Python.gitignore" ;;
    cs)  echo "https://raw.githubusercontent.com/github/gitignore/main/VisualStudio.gitignore" ;;
    mix) echo "" ;;
    *)   die "Unknown language: $1" ;;
  esac
}

# ---------- Parse args ----------
[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)        usage ;;
    --lang)           LANG="$2"; shift 2 ;;
    --description)    DESCRIPTION="$2"; shift 2 ;;
    --public)         VISIBILITY="public"; shift ;;
    --no-team)        GRANT_TEAMS="false"; shift ;;
    --dry-run)        DRY_RUN="true"; shift ;;
    -*)               die "Unknown option: $1" ;;
    *)                [[ -z "$REPO_NAME" ]] && REPO_NAME="$1" || die "Multiple repo names: $REPO_NAME, $1"; shift ;;
  esac
done

# ---------- Validate ----------
[[ -z "$REPO_NAME" ]] && die "Repo name required"
[[ -z "$LANG" ]]      && die "--lang required (ts|py|cs|mix)"
[[ ! "$LANG" =~ ^(ts|py|cs|mix)$ ]] && die "--lang must be one of: ts, py, cs, mix"
[[ ! -f "$LABELS_FILE" ]] && die "Labels file not found: $LABELS_FILE"
[[ ! -f "${TEMPLATES_DIR}/${LANG}.yml" ]] && die "Dependabot template not found: ${TEMPLATES_DIR}/${LANG}.yml"

command -v gh >/dev/null   || die "gh CLI not found"
command -v git >/dev/null  || die "git not found"
command -v jq >/dev/null   || die "jq not found"
command -v curl >/dev/null || die "curl not found"

gh auth status >/dev/null 2>&1 || die "gh not authenticated — run: gh auth login"

# ---------- Confirm ----------
echo ""
echo "About to create:"
echo "  Repo:        ${ORG}/${REPO_NAME}"
echo "  Visibility:  ${VISIBILITY}"
echo "  Language:    ${LANG}"
echo "  Description: ${DESCRIPTION:-<none>}"
echo "  Grant teams: ${GRANT_TEAMS}"
echo "  Dry run:     ${DRY_RUN}"
echo ""
if [[ "$DRY_RUN" != "true" ]]; then
  read -r -p "Proceed? [y/N] " confirm
  [[ "$confirm" =~ ^[yY]$ ]] || { echo "Aborted."; exit 0; }
fi

# ---------- 1. Create the repo ----------
step "Creating repo ${ORG}/${REPO_NAME}"
DESC_FLAG=""
[[ -n "$DESCRIPTION" ]] && DESC_FLAG="--description \"${DESCRIPTION}\""
run "gh repo create '${ORG}/${REPO_NAME}' --${VISIBILITY} ${DESC_FLAG}"

# ---------- 2. Local scaffold ----------
TMPDIR="$(mktemp -d)"
trap "rm -rf '$TMPDIR'" EXIT
cd "$TMPDIR"

step "Scaffolding files locally in $TMPDIR"

# README
cat > README.md <<EOF
# ${REPO_NAME}

${DESCRIPTION:-_Add a short description._}

## Status

🚧 Bootstrap — not yet implemented.

## Development

\`\`\`bash
# TODO: add setup instructions
\`\`\`

## Contributing

See [CONTRIBUTING.md](https://github.com/${ORG}/.github/blob/main/CONTRIBUTING.md) in the org-level \`.github\` repo.

## Security

See [SECURITY.md](https://github.com/${ORG}/.github/blob/main/SECURITY.md). Report vulnerabilities privately.
EOF
log "README.md"

# .gitignore
GIURL="$(gitignore_url "$LANG")"
if [[ -n "$GIURL" ]]; then
  curl -fsSL "$GIURL" -o .gitignore || log "WARN: failed to fetch .gitignore from $GIURL"
  log ".gitignore (from github/gitignore for ${LANG})"
else
  cat > .gitignore <<'EOF'
# Generic ignores — adjust per language used in this repo
.DS_Store
.env
.env.local
*.log
node_modules/
__pycache__/
*.pyc
bin/
obj/
.vs/
.vscode/
.idea/
EOF
  log ".gitignore (generic, mixed language)"
fi

# dependabot.yml
mkdir -p .github
cp "${TEMPLATES_DIR}/${LANG}.yml" .github/dependabot.yml
log ".github/dependabot.yml (${LANG} template)"

# LICENSE — proprietary by default (private repos), MIT only if --public
if [[ "$VISIBILITY" == "public" ]]; then
  cat > LICENSE <<EOF
MIT License

Copyright (c) $(date +%Y) Jigen SAGL

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
EOF
  log "LICENSE (MIT — public repo)"
else
  cat > LICENSE <<EOF
PROPRIETARY AND CONFIDENTIAL

Copyright (c) $(date +%Y) Jigen SAGL. All rights reserved.

This source code and all associated files (the "Software") are the
proprietary and confidential property of Jigen SAGL. Possession or use of
this Software does not convey any rights to reproduce, disclose its
contents, manufacture, use, or sell anything that it may describe, in
whole or in part, without the specific prior written permission of
Jigen SAGL.

Unauthorized copying, distribution, modification, public display, public
performance, or use of this Software, via any medium, is strictly
prohibited and may result in civil and criminal penalties under applicable
law.

This Software is provided "AS IS", without warranty of any kind, express
or implied, including but not limited to the warranties of merchantability,
fitness for a particular purpose, and noninfringement. In no event shall
Jigen SAGL be liable for any claim, damages, or other liability, whether
in an action of contract, tort, or otherwise, arising from, out of, or in
connection with the Software or the use or other dealings in the Software.

For licensing inquiries, contact: legal@jigen.example
EOF
  log "LICENSE (Proprietary — Jigen SAGL)"
fi

# ---------- 3. Initial commit + push ----------
step "Initial commit and push"
run "git init -b main >/dev/null"
run "git remote add origin 'https://github.com/${ORG}/${REPO_NAME}.git'"
run "git add -A"
run "git commit -S -m 'chore: bootstrap repository

Initial scaffold via scripts/bootstrap-repo.sh:
- README, LICENSE (MIT)
- .gitignore (${LANG})
- .github/dependabot.yml (${LANG} template)' >/dev/null"
run "git push -u origin main"

# ---------- 4. Grant team access ----------
if [[ "$GRANT_TEAMS" == "true" ]]; then
  step "Granting team access"
  run "gh api -X PUT 'orgs/${ORG}/teams/engineering/repos/${ORG}/${REPO_NAME}' -f permission=push >/dev/null"
  log "engineering → write"
  run "gh api -X PUT 'orgs/${ORG}/teams/security/repos/${ORG}/${REPO_NAME}' -f permission=pull >/dev/null"
  log "security → read"
fi

# ---------- 5. Enable Private Vulnerability Reporting (non-fatal) ----------
step "Enabling Private Vulnerability Reporting"
if [[ "$DRY_RUN" == "true" ]]; then
  log "[dry-run] gh api -X PUT 'repos/${ORG}/${REPO_NAME}/private-vulnerability-reporting'"
else
  if gh api -X PUT "repos/${ORG}/${REPO_NAME}/private-vulnerability-reporting" >/dev/null 2>&1; then
    log "PVR enabled"
  else
    log "WARN: PVR enable failed (may need manual retry — newly-created private repos sometimes 404)"
    log "      Retry with: gh api -X PUT 'repos/${ORG}/${REPO_NAME}/private-vulnerability-reporting'"
  fi
fi

# ---------- 6. Apply standard labels (delegates to sync-labels.sh) ----------
step "Applying standard labels (via sync-labels.sh)"
SYNC_FLAGS="--repo ${REPO_NAME} --delete-extra"
[[ "$DRY_RUN" == "true" ]] && SYNC_FLAGS="${SYNC_FLAGS} --dry-run"
# Auto-confirm the sync prompt
echo "y" | "${SCRIPT_DIR}/sync-labels.sh" ${SYNC_FLAGS} | sed 's/^/    /'

# ---------- Done ----------
echo ""
echo "✅ Done. Repo ready at: https://github.com/${ORG}/${REPO_NAME}"
echo ""
echo "Next steps:"
echo "  • Clone: gh repo clone ${ORG}/${REPO_NAME}"
echo "  • Set up CI workflow under .github/workflows/"
echo "  • Add status checks to the org default-branch-protection ruleset"
echo "    once you know your CI job names (Settings → Rulesets at org level)"
