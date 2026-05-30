# 1. Repo bootstrap strategy: script vs GitHub-native repository templates

- **Status:** Proposed
- **Date:** 2026-05-30
- **Deciders:** @imperugo (pending ratification)
- **Context issue:** [Jigen-lab/ops#32](https://github.com/Jigen-lab/ops/issues/32)

## Context

Provisioning a new `Jigen-lab` repo today is one script, `scripts/bootstrap-repo.sh`,
which does three distinct kinds of work:

1. **File-copy** — `README`, `LICENSE`, `.gitignore`, `.github/dependabot.yml`,
   `.github/workflows/ai-closure-summary.yml`, and (as of ops#32) the issue/PR
   templates.
2. **API orchestration** — `gh api` for team grants, label sync, Private
   Vulnerability Reporting, and the Actions create-PR permission.
3. **Logging + dry-run** — an interactive preview/confirm wrapper.

GitHub offers a native feature, [template repositories](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-template-repository),
that copies a repo's tree on `gh repo create --template`. ops#32 asks whether we
should lean on it — fully or partially — instead of the file-copy half of the
script.

This ADR records the evaluation (the "spike" deliverable of ops#32) and a
recommendation. It does **not** itself change `bootstrap-repo.sh`'s architecture.

## What GitHub template repositories do — and don't

| Capability | Template repo | `bootstrap-repo.sh` |
|---|---|---|
| Copy a file tree into a new repo | ✅ native, one click / `--template` | ✅ explicit `cp` per file |
| Per-language variation (`--lang ts\|py\|cs\|mix`) | ❌ one tree per template repo → 4 template repos | ✅ one `--lang` flag |
| Team grants, PVR, label sync, Actions perms | ❌ no post-create hooks | ✅ `gh api` |
| Compose multiple templates | ❌ exactly one template per repo | ✅ N/A (it's a script) |
| Keep existing repos in sync afterwards | ❌ one-time copy at creation only | ➖ separate `sync-*.sh` tools |
| Auditability for a newcomer | ➖ "what's in the template repo?" | ✅ one readable bash file |

The decisive gaps: template repos cover **only** point 1 (file-copy), can't run
point 2 (the API orchestration that is the actual value of bootstrap), and
**don't compose** — every `--lang` variant would need its own template repo
(`repo-template-py`, `repo-template-ts`, `repo-template-cs`, `repo-template-mix`),
each maintained in lockstep.

## Options considered

### Option A — Status quo (keep the script as the single entry point)

`bootstrap-repo.sh` stays the one tool; ops#32 just adds issue/PR-template
copying to its file-copy phase (already done in the PR this ADR ships with).

- ➕ One tool, one mental model, one place to change a default.
- ➕ No new template repos to keep in sync with the script.
- ➕ Bash + `gh` + `jq` + `curl` only — matches the repo's "no new runtime" contract.
- ➖ The script keeps growing as defaults accumulate.

### Option B — Hybrid (GitHub template repo for files + slimmed script for APIs)

`Jigen-lab/repo-template-<lang>` repos hold the file tree; `bootstrap-repo.sh`
shrinks to `gh repo create --template …` plus the API-orchestration phase.

- ➕ The file tree becomes browsable/editable as a normal repo (nice for the README/LICENSE).
- ➖ Defaults now live in **two** places (template repos + script) — exactly the
  drift ops#32 is trying to eliminate by making repos self-contained.
- ➖ 3–4 template repos to maintain in lockstep (one per `--lang`).
- ➖ The script still needs the whole API phase, so we don't actually delete much code.

### Option C — Full migration to template repositories

Drop the script; rely entirely on `gh repo create --template`.

- ➖ Loses team grants, PVR, label sync, Actions-PR permission — the parts that
  make a repo *org-compliant*, not just *populated*. These would regress to manual.
- ➖ Hard no against the org ruleset/labels-are-central philosophy.

## Decision

**Adopt Option A (status quo, script-centric).** Keep `bootstrap-repo.sh` as the
single bootstrap entry point and extend its file-copy phase with the issue/PR
templates (shipped alongside this ADR). Do **not** introduce GitHub template
repositories at this time.

Rationale: the script's real value is the API-orchestration phase, which template
repos cannot do. Template repos would solve only the cheap half (file-copy) while
adding multi-repo maintenance and reintroducing the very source-of-truth drift
ops#32 set out to remove. The hybrid model splits defaults across two surfaces for
little code savings.

## Consequences

- `bootstrap-repo.sh` remains the one tool; new defaults are added to it.
- Issue/PR templates are read from this repo's own `.github/` (single source of
  truth) by both `bootstrap-repo.sh` (new repos) and `scripts/sync-templates.sh`
  (existing repos) — no duplicated copy.
- Existing repos are aligned via `scripts/sync-templates.sh`, which opens a PR per
  repo rather than force-writing — consistent with "every merge is a deliberate
  human click".
- **Revisit if:** GitHub adds post-create hooks to template repos, or the number
  of file-copy defaults grows enough that a browsable template tree clearly beats
  a `cp` list. At that point Option B becomes worth re-scoring.

## Follow-ups (out of scope for this ADR)

- Align the template `labels:` fields (`bug`, `enhancement`, `needs-triage`) with
  the canonical taxonomy in `labels.json` (Issue Types + `status:` namespace), or
  add those labels to the catalog — currently `sync-labels.sh --delete-extra`
  removes them. Tracked on ops#32.
- Decide whether docs-only repos (`ops`, `playbook`, `brand-kit`, `business-ops`,
  `sales`) warrant a reduced template variant (ops#32, Punto 1).
