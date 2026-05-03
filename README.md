# .github

This repository contains **default community health files** for the [Jigen](https://github.com/Jigen-lab) organization.

Files here are automatically applied to any repo in the org that doesn't define its own version.

## Contents

| File | Purpose |
|---|---|
| `profile/README.md` | Public landing page shown on the org profile |
| `SECURITY.md` | Vulnerability disclosure policy |
| `CONTRIBUTING.md` | Contribution guidelines |
| `CODE_OF_CONDUCT.md` | Community code of conduct |
| `.github/PULL_REQUEST_TEMPLATE.md` | Default PR template |
| `.github/ISSUE_TEMPLATE/*.yml` | Default issue forms (bug, feature) |
| `.github/CODEOWNERS` | Default code owners (overridden per-repo) |
| `.github/dependabot.yml` | **Template only** — copy to each repo (not auto-applied) |

## How GitHub resolves these files

For most files, GitHub looks for them in this priority order:
1. The repo's own `.github/` or root
2. This `.github` repo (org-wide fallback)

`CODEOWNERS` and `dependabot.yml` are **per-repo only** — the versions here are reference templates.
