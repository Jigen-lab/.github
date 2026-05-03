# Contributing to Jigen

Thanks for your interest in contributing! This document covers the conventions used across all Jigen repositories.

## Workflow

1. **Open an issue first** for non-trivial changes — we want to align on scope before code is written.
2. **Fork & branch** from `main`. Use a descriptive branch name: `feat/xyz`, `fix/xyz`, `chore/xyz`, `docs/xyz`.
3. **Commit** following [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`, `perf:`, `ci:`.
4. **Sign your commits** — all commits MUST be GPG-signed (`git commit -S`). Branch protection rejects unsigned commits on `main`.
5. **Open a Pull Request** against `main`. Fill in the PR template completely.
6. **Wait for review**. At least one approval from `@Jigen-lab/engineering` is required, plus passing CI.

## Code Standards

- Run linters and formatters before pushing — most repos have pre-commit hooks configured.
- Add tests for new behavior. Bug fixes should include a regression test.
- Keep PRs focused: one logical change per PR.
- Update documentation alongside code changes.

## Reviews

- Reviewers should respond within 2 business days.
- Use "Request changes" only for blocking issues; use "Comment" for suggestions.
- Conversations must be resolved before merge.
- Squash & merge is the default merge strategy (forced by repo rulesets).

## Reporting Bugs / Requesting Features

Use the issue templates in the repository. They contain the structured fields we need for triage.

## Code of Conduct

By participating, you agree to abide by our [Code of Conduct](./CODE_OF_CONDUCT.md).

## Questions?

Open a discussion in the relevant repo or reach the engineering team via `@Jigen-lab/engineering`.
