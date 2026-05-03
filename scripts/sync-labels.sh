#!/usr/bin/env bash
#
# sync-labels.sh — sync labels.json to one repo, all repos, or a list.
#
# Usage:
#   ./scripts/sync-labels.sh --all                    Sync all org repos
#   ./scripts/sync-labels.sh --repo <name> [...]      Sync specific repo(s)
#   ./scripts/sync-labels.sh --all --delete-extra     Also delete labels NOT in labels.json
#   ./scripts/sync-labels.sh --all --dry-run          Preview changes
#
# Behavior (idempotent):
#   - Labels in labels.json that don't exist  → CREATE
#   - Labels in labels.json that exist        → UPDATE color/description if different
#   - Labels in repo NOT in labels.json       → kept (use --delete-extra to remove)
#
# GitHub default labels (bug, documentation, duplicate, enhancement,
#   good first issue, help wanted, invalid, question, wontfix) are removed
#   automatically when --delete-extra is set, since they conflict with our
#   `status: *` and `area: *` taxonomy.
#
set -euo pipefail

ORG="Jigen-lab"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABELS_FILE="${SCRIPT_DIR}/labels.json"

REPOS=()
SYNC_ALL="false"
DELETE_EXTRA="false"
DRY_RUN="false"

die()  { echo "ERROR: $*" >&2; exit 1; }
log()  { echo "    $*"; }
step() { echo "▶ $*"; }

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# ---------- Parse args ----------
[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)       usage ;;
    --all)           SYNC_ALL="true"; shift ;;
    --repo)          REPOS+=("$2"); shift 2 ;;
    --delete-extra)  DELETE_EXTRA="true"; shift ;;
    --dry-run)       DRY_RUN="true"; shift ;;
    -*)              die "Unknown option: $1" ;;
    *)               die "Unknown argument: $1" ;;
  esac
done

[[ "$SYNC_ALL" == "false" && ${#REPOS[@]} -eq 0 ]] && die "Specify --all or --repo <name>"
[[ ! -f "$LABELS_FILE" ]] && die "Labels file not found: $LABELS_FILE"
command -v gh >/dev/null || die "gh CLI not found"
command -v jq >/dev/null || die "jq not found"

# ---------- Discover repos ----------
if [[ "$SYNC_ALL" == "true" ]]; then
  step "Listing all repos in ${ORG}"
  mapfile -t REPOS < <(gh api --paginate "orgs/${ORG}/repos" --jq '.[].name')
  log "Found ${#REPOS[@]} repos"
fi

echo ""
echo "Will sync ${#REPOS[@]} repo(s):"
printf "  • %s\n" "${REPOS[@]}"
echo ""
echo "Source: ${LABELS_FILE} ($(jq length "$LABELS_FILE") labels)"
echo "Delete extras: ${DELETE_EXTRA}"
echo "Dry run: ${DRY_RUN}"
echo ""

if [[ "$DRY_RUN" != "true" ]]; then
  read -r -p "Proceed? [y/N] " confirm
  [[ "$confirm" =~ ^[yY]$ ]] || { echo "Aborted."; exit 0; }
fi

# ---------- Sync function ----------
url_encode() {
  # URL-encode using jq (handles spaces, special chars)
  jq -rn --arg v "$1" '$v | @uri'
}

sync_repo() {
  local repo="$1"
  step "Syncing ${ORG}/${repo}"

  # Build set of desired label names
  local desired_names
  desired_names=$(jq -r '.[].name' "$LABELS_FILE")

  # Fetch current labels
  local current_labels
  current_labels=$(gh api --paginate "repos/${ORG}/${repo}/labels" 2>/dev/null \
    || { log "  (skipped: cannot read labels — does repo exist?)"; return; })

  # Pass 1: create or update each desired label
  local i name color desc current_color current_desc encoded
  for i in $(jq -r 'keys[]' "$LABELS_FILE"); do
    name=$(jq -r ".[$i].name" "$LABELS_FILE")
    color=$(jq -r ".[$i].color" "$LABELS_FILE")
    desc=$(jq -r ".[$i].description" "$LABELS_FILE")
    encoded=$(url_encode "$name")

    current_color=$(echo "$current_labels" | jq -r --arg n "$name" '.[] | select(.name==$n) | .color // ""')
    current_desc=$(echo "$current_labels" | jq -r --arg n "$name" '.[] | select(.name==$n) | .description // ""')

    if [[ -z "$current_color" ]]; then
      # Create
      if [[ "$DRY_RUN" == "true" ]]; then
        log "  + create: $name (#$color)"
      else
        gh api -X POST "repos/${ORG}/${repo}/labels" \
          -f name="$name" -f color="$color" -f description="$desc" >/dev/null \
          && log "  + created: $name" \
          || log "  ! failed: $name"
      fi
    elif [[ "$current_color" != "$color" || "$current_desc" != "$desc" ]]; then
      # Update
      if [[ "$DRY_RUN" == "true" ]]; then
        log "  ~ update: $name (#${current_color} → #${color})"
      else
        gh api -X PATCH "repos/${ORG}/${repo}/labels/${encoded}" \
          -f new_name="$name" -f color="$color" -f description="$desc" >/dev/null \
          && log "  ~ updated: $name" \
          || log "  ! failed: $name"
      fi
    fi
  done

  # Pass 2: delete extras if requested
  if [[ "$DELETE_EXTRA" == "true" ]]; then
    local current_names extra_names
    current_names=$(echo "$current_labels" | jq -r '.[].name')
    extra_names=$(comm -23 <(echo "$current_names" | sort) <(echo "$desired_names" | sort))
    if [[ -n "$extra_names" ]]; then
      while IFS= read -r name; do
        encoded=$(url_encode "$name")
        if [[ "$DRY_RUN" == "true" ]]; then
          log "  - delete: $name"
        else
          gh api -X DELETE "repos/${ORG}/${repo}/labels/${encoded}" >/dev/null \
            && log "  - deleted: $name" \
            || log "  ! delete failed: $name"
        fi
      done <<< "$extra_names"
    fi
  fi
}

for repo in "${REPOS[@]}"; do
  sync_repo "$repo"
done

echo ""
echo "✅ Done."
