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
  # macOS ships bash 3.2, which has no `mapfile` — read into the array by hand
  # so the script runs from any laptop (the repo's portability contract).
  REPOS=()
  while IFS= read -r _name; do
    [[ -n "$_name" ]] && REPOS+=("$_name")
  done < <(gh api --paginate "orgs/${ORG}/repos" \
    --jq '.[] | select(.archived==false) | .name' | grep -vxF '.github')
  log "Found ${#REPOS[@]} repos (excluding the .github source repo)"
fi

# Defensive: drop the source repo if it was passed explicitly. The
# "${arr[@]+"${arr[@]}"}" form is the bash-3.2-safe way to expand a possibly
# empty array under `set -u` (a bare "${arr[@]}" trips "unbound variable").
FILTERED=()
for r in "${REPOS[@]+"${REPOS[@]}"}"; do [[ "$r" == ".github" ]] || FILTERED+=("$r"); done
REPOS=("${FILTERED[@]+"${FILTERED[@]}"}")
[[ ${#REPOS[@]} -eq 0 ]] && die "No target repos after filtering"

# ---------- Codex coverage report ----------
# Returns non-zero only when App coverage could not be determined (so a
# --check-codex run in CI fails loudly rather than looking like full coverage).
codex_report() {
  step "Codex (${CODEX_APP_SLUG}) coverage report"
  local installs selection rc=0
  # Probe the installations endpoint first so we can tell "no admin:org / API
  # error" apart from "App genuinely not installed".
  if ! installs=$(gh api "orgs/${ORG}/installations" --jq '.installations[].app_slug' 2>&1); then
    log "✗ Could not read org installations (likely missing the admin:org scope)."
    log "    Refresh with: gh auth refresh -s admin:org   then re-run --check-codex"
    rc=1
  elif ! grep -qxF "$CODEX_APP_SLUG" <<<"$installs"; then
    log "✗ The ${CODEX_APP_SLUG} App is NOT installed on ${ORG}."
    log "    Install: https://github.com/apps/${CODEX_APP_SLUG}"
    rc=1
  else
    selection=$(gh api "orgs/${ORG}/installations" \
      --jq ".installations[] | select(.app_slug==\"${CODEX_APP_SLUG}\") | .repository_selection" 2>/dev/null)
    case "$selection" in
      all)      log "✓ App installed org-wide (repository_selection: all) — every repo is covered at the App level." ;;
      selected) log "⚠ App installed with repository_selection: selected — confirm each target repo is in the selected set:"
                log "    https://github.com/organizations/${ORG}/settings/installations" ;;
      *)        log "? Unexpected repository_selection: '${selection}'"; rc=1 ;;
    esac
  fi

  echo ""
  log "Per-repo Codex ENVIRONMENT bootstrap — manual, not detectable via gh:"
  log "(first '@codex review' on a repo may prompt 'create an environment for this repo')"
  for r in "${REPOS[@]}"; do
    log "  - [ ] ${ORG}/${r}"
  done
  return "$rc"
}

if [[ "$CHECK_CODEX_ONLY" == "true" ]]; then
  codex_report   # propagate its exit code so CI can key off it
  exit $?
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
  [[ "$confirm" =~ ^[yY]([eE][sS])?$ ]] || { echo "Aborted."; exit 0; }
fi

# ---------- Helpers ----------
# Echo the blob SHA of <path> on <repo>@<ref>; empty output means the file is
# absent (HTTP 404 — an expected, benign case). Returns NON-ZERO on a real API
# error (rate-limit, auth, 5xx, network) so the caller can bail on the repo
# instead of mistaking an error for "file differs" / "file absent".
remote_blob_sha() {
  local repo="$1" path="$2" ref="$3" out
  if out=$(gh api "repos/${ORG}/${repo}/contents/${path}?ref=${ref}" --jq '.sha' 2>&1); then
    echo "$out"; return 0
  fi
  # gh exited non-zero: a genuine 404 is "absent"; anything else is a real error.
  grep -qiE 'not found|HTTP 404' <<<"$out" && { echo ""; return 0; }
  return 1
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

  # Decide which files are out of date. --no-filters keeps the local hash in
  # terms of raw bytes (the same bytes put_file base64-encodes), so a future
  # .gitattributes text/CRLF rule can't cause a perpetual "out of date" loop.
  local pair path src local_sha remote_sha
  local -a need_paths=() need_srcs=()
  for pair in "${TEMPLATE_MAP[@]}"; do
    path="${pair%%:*}"; src="${pair#*:}"
    local_sha=$(git hash-object --no-filters "$src")
    if ! remote_sha=$(remote_blob_sha "$repo" "$path" "$default_branch"); then
      log "  ! API error reading ${path}@${default_branch} — skipping repo (state unknown)"
      return
    fi
    if [[ "$local_sha" != "$remote_sha" ]]; then
      need_paths+=("$path"); need_srcs+=("$src")
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
  head_sha=$(gh api "repos/${ORG}/${repo}/git/ref/heads/${default_branch}" --jq '.object.sha' 2>/dev/null) \
    || { log "  ! could not read head of ${default_branch} — skipping repo"; return; }
  [[ -z "$head_sha" || "$head_sha" == "null" ]] && { log "  ! empty head sha for ${default_branch} — skipping repo"; return; }
  if gh api "repos/${ORG}/${repo}/git/ref/heads/${PR_BRANCH}" >/dev/null 2>&1; then
    log "  branch ${PR_BRANCH} already exists — refreshing files on it"
  else
    gh api -X POST "repos/${ORG}/${repo}/git/refs" \
      -f ref="refs/heads/${PR_BRANCH}" -f sha="${head_sha}" >/dev/null \
      || { log "  ! could not create branch ${PR_BRANCH}"; return; }
    log "  created branch ${PR_BRANCH}"
  fi

  # Write each out-of-date file onto the branch. Track failures so a partial
  # write never produces a PR that looks complete (a half-written PR reads as
  # success otherwise).
  local i branch_sha local_sha write_failures=0
  for i in "${!need_paths[@]}"; do
    # Re-resolve the sha on the working branch (may differ from default if the
    # branch pre-existed with partial content).
    if ! branch_sha=$(remote_blob_sha "$repo" "${need_paths[$i]}" "${PR_BRANCH}"); then
      log "  ! API error reading ${need_paths[$i]}@${PR_BRANCH}"
      write_failures=$((write_failures + 1)); continue
    fi
    # Skip the PUT when the branch already carries identical bytes (avoids a
    # GitHub 422 "no changes" that would otherwise log as a spurious failure).
    local_sha=$(git hash-object --no-filters "${need_srcs[$i]}")
    if [[ "$branch_sha" == "$local_sha" ]]; then
      log "  = ${need_paths[$i]} (already current on branch)"; continue
    fi
    if put_file "$repo" "${need_paths[$i]}" "${need_srcs[$i]}" "$branch_sha"; then
      log "  ↑ ${need_paths[$i]}"
    else
      log "  ! failed to write ${need_paths[$i]}"
      write_failures=$((write_failures + 1))
    fi
  done

  if [[ "$write_failures" -gt 0 ]]; then
    log "  ! ${write_failures} file(s) failed to write — NOT opening PR (branch left for inspection)"
    return 1
  fi

  # Don't open (or re-open) a PR if one already exists for this branch — check
  # ALL states so a deliberately-closed PR is not resurrected on a re-run.
  local existing_state existing_url
  read -r existing_state existing_url < <(gh api "repos/${ORG}/${repo}/pulls?head=${ORG}:${PR_BRANCH}&state=all" \
    --jq '.[0] | "\(.state // "") \(.html_url // "")"' 2>/dev/null || echo "")
  case "$existing_state" in
    open)   log "  ↻ PR already open: ${existing_url} (files refreshed)"; return ;;
    closed) log "  ⤫ a previous PR on ${PR_BRANCH} was closed unmerged: ${existing_url} — not re-opening (reopen manually if intended)"; return ;;
  esac

  local url
  if url=$(gh api -X POST "repos/${ORG}/${repo}/pulls" \
            -f title="chore: add standard issue & PR templates" \
            -f head="${PR_BRANCH}" \
            -f base="${default_branch}" \
            -f body="$(pr_body)" \
            --jq '.html_url' 2>&1); then
    log "  ✓ PR opened: ${url}"
  elif grep -qiE 'already exist' <<<"$url"; then
    log "  ↻ PR already exists for ${PR_BRANCH} (files refreshed)"
  else
    log "  ! failed to open PR (branch pushed; open manually if needed)"
  fi
}

for repo in "${REPOS[@]}"; do
  sync_repo "$repo" || log "  ! error syncing ${repo} — continuing"
done

# ---------- Codex report (always, at the end) ----------
# Informational here — an undeterminable Codex state must not fail a rollout
# that already opened its PRs, so its exit code is swallowed (use --check-codex
# for the exit-code-bearing variant).
echo ""
codex_report || true

echo ""
echo "✅ Done."
