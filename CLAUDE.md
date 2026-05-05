# Claude Code instructions for the org `.github` repo (formerly dotgithub-repo)

This is the **org-tooling repo** for `Jigen-lab` — bootstrap scripts, label catalog, ruleset config, and shared workflow / dependabot templates that get installed into every new Jigen-lab repository. Read this file before doing any work here.

## Repo philosophy in 3 lines

1. **Bash + JSON, no dependencies.** Every script is plain bash and uses only `gh`, `git`, `jq`, `curl`. No Python, no Node. Easier to audit and easier for newcomers to run from any laptop.
2. **Templates ship, not patch.** `workflow-templates/` and `dependabot-templates/` are copy-only — the bootstrap script reads them, fills placeholders, and writes the result into the new repo. We don't `gh api PATCH` existing repos from here.
3. **Labels and rulesets are managed centrally.** `labels.json` is the canonical label set; `sync-labels.sh` reconciles each repo against it. `ruleset.json` is documented but applied via the GitHub UI / org-level rulesets.

## Layout

```
bootstrap-repo.sh              creates a new Jigen-lab repo with sensible defaults
                                (visibility, teams, labels, dependabot, AI Stage 5 workflow,
                                 PVR, Actions create-PR permission)
sync-labels.sh                 reconciles existing repos against labels.json
labels.json                    org-canonical label catalog (28 entries:
                                priority/status/area/impact + generics)
ruleset.json                   reference for the org default-branch ruleset
                                (NOT applied by any script — paste-into-UI)
workflow-templates/            YAML templates copied into new repos
                                (currently: ai-closure-summary.yml)
dependabot-templates/          dependabot.yml templates per language
                                (python, ts, dotnet, go, rust)
README.md                      top-level overview
scripts/README.md              full reference for both scripts and the issue-types
                                vs labels model
```

## bootstrap-repo.sh

The most-used script. Provisions a new repo end-to-end:

```bash
./bootstrap-repo.sh <repo-name> --lang <ts|python|dotnet|go|rust> [--description "..."] [--public] [--no-teams] [--dry-run]
```

What it does (in order):
1. `gh repo create` (private by default, public via `--public`)
2. Scaffolds `README.md` + `.gitignore` (from github/gitignore for the language) + `.github/dependabot.yml` (from `dependabot-templates/<lang>.yml`) + `.github/workflows/ai-closure-summary.yml` + `LICENSE` (proprietary Jigen)
3. Initial commit + push
4. Grants team access (`@Jigen-lab/engineering` write, `@Jigen-lab/security` read)
5. Enables Private Vulnerability Reporting (sometimes 404s on brand-new repos — retry manually if so)
6. Enables Actions create-PR permission (`default_workflow_permissions: write`, `can_approve_pull_request_reviews: true`)
7. Runs `sync-labels.sh` to apply the canonical label set

The script is **interactive by default** — it shows a preview and waits for `y` confirmation. Pass via stdin (`printf "y\n" | ./bootstrap-repo.sh ...`) or pipe through `yes` for non-interactive runs.

## sync-labels.sh

Reconciles repos against `labels.json`:

```bash
./sync-labels.sh <repo-name>           # single repo
./sync-labels.sh --all                 # every repo in the org
./sync-labels.sh --dry-run <repo-name> # show diffs without applying
```

Default behaviour: creates missing labels, updates description/color of existing ones, **deletes** labels not in `labels.json`. The deletion step removed GitHub's own defaults (`bug`, `documentation`, `enhancement`, etc.) on first run for every repo — that was intentional.

## When you change a script

1. Edit the `.sh` directly. Keep it bash-only — no Python imports, no Node CLI dependencies.
2. Test on a sacrificial repo with `--dry-run` first if available.
3. Open a PR with `chore(scripts):` or `feat(scripts):` prefix. Squash merge.
4. Bumping behavior that affects existing repos? Re-run `sync-labels.sh --all` to roll out.

## When you change labels.json or ruleset.json

- `labels.json`: open a PR. After merge, re-run `sync-labels.sh --all` to propagate to every repo. Be aware that **deletion** of a label removes it from every existing issue across the org — review carefully before committing a removal.
- `ruleset.json`: this file is documentation, not applied by any script. Update it AND the org-level ruleset in the GitHub UI in the same change window — it's currently a manual sync.

## When you add a new template

- `workflow-templates/<new>.yml`: also patch `bootstrap-repo.sh` to copy it (it currently hardcodes the list of workflow files to install).
- `dependabot-templates/<lang>.yml`: also patch `bootstrap-repo.sh` to add a new option for `--lang`.

## What NOT to do

- Don't introduce a new language runtime (Python, Node, etc.) here. Bash + jq + curl + gh is the contract.
- Don't `gh api PATCH` an existing repo from a script in this repo. The model is "bootstrap once + sync labels"; deeper rolling changes belong in their consuming repo's CI.
- Don't commit a real label colour change without running `sync-labels.sh --dry-run --all` first to gauge how many issues' visual identity will shift.
- Don't remove a workflow template without also removing the call in `bootstrap-repo.sh` — orphan `cp` of a missing file fails the script silently for a moment then loud.

## See also

- [`Jigen-lab/playbook/onboarding/creating-a-new-repo.md`](https://github.com/Jigen-lab/playbook/blob/main/onboarding/creating-a-new-repo.md) — the user-facing prose for `bootstrap-repo.sh`
- [`Jigen-lab/playbook/conventions/labels-and-issue-types.md`](https://github.com/Jigen-lab/playbook/blob/main/conventions/labels-and-issue-types.md) — the canonical reference for what labels mean
- [`Jigen-lab/github-workflows`](https://github.com/Jigen-lab/github-workflows) — `ai-closure-summary.yml` lives here AND there (single source: this repo, copied into new repos at bootstrap time, but maintained on the consumer side after bootstrap)
