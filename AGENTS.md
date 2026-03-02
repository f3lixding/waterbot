# Repository Guidelines

## Project Structure & Module Organization
- docs/: Source of truth for design and planning.
  - docs/DOODLE.md: High‑level WATERBOT design notes and open questions.
  - docs/DIVISION_OF_LABOR.md: Areas of concern and responsibilities.
- No application code or build system is present yet.

## Build, Test, and Development Commands
- View docs: open the Markdown files in your editor or viewer.
- Optional lint: run markdown linters/formatters if installed, e.g.
  - markdownlint: `markdownlint "docs/**/*.md"`
  - Prettier: `prettier -w "docs/**/*.md"`
- Link check (optional): `npx markdown-link-check -r docs`
  These tools are not required; use them if available in your environment.

## Coding Style & Naming Conventions
- Markdown: use ATX headings (`#`, `##`), sentence‑case titles, and fenced code blocks.
- Lists: prefer `-` bullets; keep indentation consistent.
- Line length: aim for ≤100 chars; wrap intentionally for readability.
- Filenames: UPPER_SNAKE for reference docs (e.g., `DOODLE.md`), kebab‑case for multiword topics (e.g., `plant-id-strategy.md`).
- Formatting: keep callouts compact; favor concise, actionable prose over speculation.

## Testing Guidelines
- No automated tests yet. Validate docs by:
  - Ensuring all links resolve and relative paths are correct.
  - Running optional link and markdown linters (see above).
  - Keeping sections scoped and cross‑linking related topics (e.g., from DOODLE to DIVISION_OF_LABOR).

## Commit & Pull Request Guidelines
- Commits: imperative mood, concise scope. Suggested prefixes: `docs:`, `chore:`, `meta:`.
  - Example: `docs: add navigation questions to DOODLE`
- PRs: include a clear summary, why the change is needed, and affected files.
  - Link any related issues or design questions.
  - Add screenshots only when visual rendering matters.

## Version Control (jj)
- VCS: This repo uses Jujutsu (`jj`), see `.jj/`.
- Common commands:
  - Status: `jj st`
  - Create change: `jj new` (or branch with `jj new -m "docs: update guidelines"`)
  - Describe/edit message: `jj describe -m "docs: refine testing guidance"`
  - Show change: `jj show`
  - Amended commits: changes are stacked; use `jj squash` or `jj undo` as needed.
- Interop with Git (if configured):
  - Import: `jj git import`
  - Export/push: `jj git push`
  - Fetch: `jj git fetch`
  Keep messages in imperative mood and group logical changes per change.

## Contributor Tips
- When adding a new topic, create a focused doc in `docs/` and link it from `DOODLE.md`.
- Prefer small, incremental PRs; state open questions explicitly to invite discussion.
