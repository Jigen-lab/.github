#!/usr/bin/env bash
#
# sync-templates.sh — roll the org issue/PR templates out to existing repos
#                     by opening a pull request on each one.
#
# Usage:
#   ./scripts/sync-templates.sh --all                 Open template PRs on all org repos
#   ./scripts/sync-templates.sh --repo <name> [...]   Target specific repo(s)
#   ./scripts/sync-templates.sh --all --dry-run       Preview — open nothing
#   ./scripts/sync-templates.sh --all --check-codex   Only print the Codex coverage report
#
# Source of truth (NOT duplicated — read straight from this repo's own .github/):
#   .github/ISSUE_TEMPLATE/bug_report.yml
#   .github/ISSUE_TEMPLATE/feature_request.yml
#   .github/ISSUE_TEMPLATE/config.yml
#   .github/PULL_REQUEST_TEMPLATE.md
#
# Behavior (idempotent):
#   - The `.github` repo itself is skipped (it is the source of truth).
#   - Per repo, each template's local blob SHA (git hash-object) is compared
#     to the file already on the repo's default branch.
#       • all four identical            → repo is up to date, NO PR is opened
#       • any missing / different       → a `chore/sync-issue-pr-templates`
#                                         branch is created and a PR opened
#   - If that branch / an open PR already exists, the files are refreshed on
#     the branch instead of opening a duplicate PR.
#
# Why PRs and not direct writes: this repo's contract is "templates ship, not
# patch" — we never push to a default branch or PATCH repo settings from here.
# Opening a PR keeps every change a deliberate human merge, exactly like the
# label sync proposes-then-applies model. Commits are created through the
# GitHub Contents API, so they are signed by GitHub's web-flow key and satisfy
# the org's signed-commits ruleset without needing a local clone per repo.
#
# Codex note: enabling the `chatgpt-codex-connector` GitHub App is an org-admin
# action and the per-repo Codex *environment* bootstrap lives in Codex's own
# backend — neither is scriptable here. This script only DETECTS and REPORTS
# App coverage and prints a manual checklist (see --check-codex / the tail of
# every run). See docs/decisions/0001-repo-bootstrap-strategy.md.
#
set -euo pipefail

ORG="Jigen-lab"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_DIR="${SCRIPT_DIR}/../.github"
CODEX_APP_SLUG="chatgpt-codex-connector"

# dest-path-in-target-repo : source-file-in-this-repo
TEMPLATE_MAP=(
  ".github/ISSUE_TEMPLATE/bug_report.yml:${GITHUB_DIR}/ISSUE_TEMPLATE/bug_report.yml"
  ".github/ISSUE_TEMPLATE/feature_request.yml:${GITHUB_DIR}/ISSUE_TEMPLATE/feature_request.yml"
  ".github/ISSUE_TEMPLATE/config.yml:${GITHUB_DIR}/ISSUE_TEMPLATE/config.yml"
  ".github/PULL_REQUEST_TEMPLATE.md:${GITHUB_DIR}/PULL_REQUEST_TEMPLATE.md"
)

PR_BRANCH="chore/sync-issue-pr-templates"

REPOS=()
SYNC_ALL="false"
DRY_RUN="false"
CHECK_CODEX_ONLY="false"

die()  { echo "ERROR: $*" >&2; exit 1; }
log()  { echo "    $*"; }
step() { echo "▶ $*"; }

usage() { sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# ---------- Parse args ----------
[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)      usage ;;
    --all)          SYNC_ALL="true"; shift ;;
    --repo)         REPOS+=("$2"); shift 2 ;;
    --dry-run)      DRY_RUN="true"; shift ;;
    --check-codex)  CHECK_CODEX_ONLY="true"; shift ;;
    -*)             die "Unknown option: $1" ;;
    *)              die "Unknown argument: $1" ;;
  esac
done

[[ "$SYNC_ALL" == "false" && ${#REPOS[@]} -eq 0 ]] && die "Specify --all or --repo <name>"
command -v gh  >/dev/null || die "gh CLI not found"
command -v jq  >/dev/null || die "jq not found"
command -v git >/dev/null || die "git not found"

# Verify every source template exists before touching any repo.
for pair in "${TEMPLATE_MAP[@]}"; do
  src="${pair#*:}"
  [[ -f "$src" ]] || die "Source template not found: $src"
done

# ---------- Discover repos ----------
if [[ "$SYNC_ALL" == "true" ]]; then
  step "Listing active (non-archived) repos in ${ORG}"
  mapfile -t REPOS < <(gh api --paginate "orgs/${ORG}/repos" \
    --jq '.[] | select(.archived==false) | .name' | grep -vxF '.github')
  log "Found ${#REPOS[@]} repos (excluding the .github source repo)"
fi

# Defensive: drop the source repo if it was passed explicitly.
FILTERED=()
for r in "${REPOS[@]}"; do [[ "$r" == ".github" ]] || FILTERED+=("$r"); done
REPOS=("${FILTERED[@]}")
[[ ${#REPOS[@]} -eq 0 ]] && die "No target repos after filtering"

# ---------- Codex coverage report ----------
codex_report() {
  step "Codex (${CODEX_APP_SLUG}) coverage report"
  local selection
  selection=$(gh api "orgs/${ORG}/installations" \
    --jq ".installations[] | select(.app_slug==\"${CODEX_APP_SLUG}\") | .repository_selection" 2>/dev/null || echo "")

  case "$selection" in
    all)
      log "✓ App installed org-wide (repository_selection: all) — every repo is covered at the App level." ;;
    selected)
      log "⚠ App installed with repository_selection: selected — confirm each target repo is in the selected set:"
      log "    https://github.com/organizations/${ORG}/settings/installations" ;;
    "")
      log "✗ Could not read the Codex App installation (needs admin:org, or the App is not installed)."
      log "    Install: https://github.com/apps/${CODEX_APP_SLUG}" ;;
    *)
      log "? Unexpected repository_selection: '${selection}'" ;;
  esac

  echo ""
  log "Per-repo Codex ENVIRONMENT bootstrap — manual, not detectable via gh:"
  log "(first '@codex review' on a repo may prompt 'create an environment for this repo')"
  for r in "${REPOS[@]}"; do
    log "  - [ ] ${ORG}/${r}"
  done
}

if [[ "$CHECK_CODEX_ONLY" == "true" ]]; then
  codex_report
  exit 0
fi

# ---------- Preview + confirm ----------
echo ""
echo "Will open template PRs on ${#REPOS[@]} repo(s):"
printf "  • %s\n" "${REPOS[@]}"
echo ""
echo "Templates (source → dest):"
for pair in "${TEMPLATE_MAP[@]}"; do
  echo "  • ${pair#*:}  →  ${pair%%:*}"
done
echo ""
echo "PR branch: ${PR_BRANCH}"
echo "Dry run:   ${DRY_RUN}"
echo ""

if [[ "$DRY_RUN" != "true" ]]; then
  read -r -p "Proceed? [y/N] " confirm
  [[ "$confirm" =~ ^[yY]$ ]] || { echo "Aborted."; exit 0; }
fi

# ---------- Helpers ----------
# Remote blob SHA of <path> on <repo>@<ref>, or empty if the file is absent.
remote_blob_sha() {
  local repo="$1" path="$2" ref="$3"
  gh api "repos/${ORG}/${repo}/contents/${path}?ref=${ref}" --jq '.sha' 2>/dev/null || true
}

# PUT a file onto the working branch (create or update).
put_file() {
  local repo="$1" path="$2" src="$3" sha="$4"
  local b64 args
  b64=$(base64 < "$src" | tr -d '\n')
  args=(-X PUT "repos/${ORG}/${repo}/contents/${path}"
        -f message="chore: add ${path}"
        -f content="${b64}"
        -f branch="${PR_BRANCH}")
  [[ -n "$sha" ]] && args+=(-f sha="${sha}")
  gh api "${args[@]}" >/dev/null
}

pr_body() {
  cat <<EOF
## Summary

Add the standard Jigen-lab issue & PR templates so this repo is self-contained
instead of relying on the implicit org-wide fallback from \`Jigen-lab/.github\`.

Files added/updated:
- \`.github/ISSUE_TEMPLATE/bug_report.yml\`
- \`.github/ISSUE_TEMPLATE/feature_request.yml\`
- \`.github/ISSUE_TEMPLATE/config.yml\`
- \`.github/PULL_REQUEST_TEMPLATE.md\`

## Related issues

Refs Jigen-lab/ops#32

## Type of change

- [x] Documentation / repo config (no functional code change)

## How was this tested

- [x] Templates are byte-identical to the source of truth in \`Jigen-lab/.github\`
- [x] Opened via \`scripts/sync-templates.sh\` (Contents API → GitHub-signed commits)

## Deployment / migration notes

None. The templates referenced labels (\`bug\`, \`enhancement\`, \`needs-triage\`)
should exist in this repo — run \`sync-labels.sh\` if any are missing.
EOF
}

# ---------- Per-repo sync ----------
sync_repo() {
  local repo="$1"
  step "Syncing ${ORG}/${repo}"

  local default_branch
  default_branch=$(gh api "repos/${ORG}/${repo}" --jq '.default_branch' 2>/dev/null) \
    || { log "  (skipped: cannot read repo — does it exist / have access?)"; return; }
  [[ -z "$default_branch" || "$default_branch" == "null" ]] && { log "  (skipped: no default branch — empty repo?)"; return; }

  # Decide which files are out of date.
  local pair path src local_sha remote_sha
  local -a need_paths=() need_srcs=() need_remote_shas=()
  for pair in "${TEMPLATE_MAP[@]}"; do
    path="${pair%%:*}"; src="${pair#*:}"
    local_sha=$(git hash-object "$src")
    remote_sha=$(remote_blob_sha "$repo" "$path" "$default_branch")
    if [[ "$local_sha" != "$remote_sha" ]]; then
      need_paths+=("$path"); need_srcs+=("$src"); need_remote_shas+=("$remote_sha")
    fi
  done

  if [[ ${#need_paths[@]} -eq 0 ]]; then
    log "  ✓ up to date (all 4 templates match) — no PR"
    return
  fi

  log "  ${#need_paths[@]} template(s) out of date: ${need_paths[*]}"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "  [dry-run] would open PR ${PR_BRANCH} → ${default_branch}"
    return
  fi

  # Ensure the working branch exists (create from default head, or reuse).
  local head_sha
  head_sha=$(gh api "repos/${ORG}/${repo}/git/ref/heads/${default_branch}" --jq '.object.sha')
  if gh api "repos/${ORG}/${repo}/git/ref/heads/${PR_BRANCH}" >/dev/null 2>&1; then
    log "  branch ${PR_BRANCH} already exists — refreshing files on it"
  else
    gh api -X POST "repos/${ORG}/${repo}/git/refs" \
      -f ref="refs/heads/${PR_BRANCH}" -f sha="${head_sha}" >/dev/null \
      || { log "  ! could not create branch ${PR_BRANCH}"; return; }
    log "  created branch ${PR_BRANCH}"
  fi

  # Write each out-of-date file onto the branch.
  local i
  for i in "${!need_paths[@]}"; do
    # Re-resolve the sha on the working branch (may differ from default if the
    # branch pre-existed with partial content).
    local branch_sha
    branch_sha=$(remote_blob_sha "$repo" "${need_paths[$i]}" "${PR_BRANCH}")
    if put_file "$repo" "${need_paths[$i]}" "${need_srcs[$i]}" "$branch_sha"; then
      log "  ↑ ${need_paths[$i]}"
    else
      log "  ! failed to write ${need_paths[$i]}"
    fi
  done

  # Open the PR if one isn't already open for this branch.
  local existing_pr
  existing_pr=$(gh api "repos/${ORG}/${repo}/pulls?head=${ORG}:${PR_BRANCH}&state=open" --jq '.[0].html_url' 2>/dev/null || true)
  if [[ -n "$existing_pr" && "$existing_pr" != "null" ]]; then
    log "  ↻ PR already open: ${existing_pr} (files refreshed)"
    return
  fi

  local url
  if url=$(gh api -X POST "repos/${ORG}/${repo}/pulls" \
            -f title="chore: add standard issue & PR templates" \
            -f head="${PR_BRANCH}" \
            -f base="${default_branch}" \
            -f body="$(pr_body)" \
            --jq '.html_url' 2>/dev/null); then
    log "  ✓ PR opened: ${url}"
  else
    log "  ! failed to open PR (branch pushed; open manually if needed)"
  fi
}

for repo in "${REPOS[@]}"; do
  sync_repo "$repo" || log "  ! error syncing ${repo} — continuing"
done

# ---------- Codex report (always, at the end) ----------
echo ""
codex_report

echo ""
echo "✅ Done."
