---
name: smart-commit
description: Analyzes all uncommitted git changes (staged, unstaged, untracked), groups them into logically related commits, presents a review table, waits for approval, then executes each commit in order. Use when the user says "commit my changes", "group my changes into commits", "create commits", or asks to commit multiple unrelated changes at once.
---

# Smart Commit

## Quick start

Run when the user has uncommitted changes and wants them grouped into meaningful commits.

## Workflow

### 1. Gather changes

```bash
git status
git diff --stat HEAD
```

Also inspect content of key changed files to understand *what* changed:
```bash
git diff HEAD -- <file>
```

For untracked files, list their contents to understand them.

### 2. Group by logical unit

Assign each changed file to exactly one group. Use these signals:

| Signal | Grouping hint |
|--------|--------------|
| Same skill/feature folder | One commit |
| Delete + matching CLAUDE.md table row removal | Same commit |
| New file + its registration/wiring | Same commit |
| Bug fix in one layer | One commit |
| Docs/reference updates with no logic change | One commit |
| Unrelated fixes in different domains | Separate commits |

### 3. Present the plan

Output a markdown table **before writing a single `git add`**:

| # | Commit message | Files |
|---|----------------|-------|
| 1 | `type: description` | `path/a`, `path/b` |
| 2 | `type: description` | `path/c` |

Then ask: **"Shall I proceed with these N commits?"**

### 4. Execute after approval

For each commit in order:
```bash
git add <files for this commit>
git commit -m "<type>: <short imperative description>"
```

After all commits, run `git log --oneline -<N+1>` to confirm.

## Commit message format

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <short imperative description>
```

| Type | When to use |
|------|-------------|
| `feat` | New capability added |
| `fix` | Corrects a bug or wrong value |
| `chore` | Maintenance — no behaviour change |
| `docs` | Documentation only |
| `refactor` | Code restructure, no new behaviour |
| `test` | Tests added or updated |
| `perf` | Performance improvement |

- Max 72 chars on the subject line
- Imperative mood: "add X", "remove Y", "fix Z" — not "added" or "fixes"
- No period at end

## Rules

- **Never commit** without explicit user approval of the plan table
- **Never use** `git add -A` or `git add .` — always name files explicitly
- **Never skip** hooks (`--no-verify`)
- **Never commit** `.env`, `env.json`, or credential files — warn the user if present
- Deleted files must be staged with `git add -f <path>` (or `git rm`)
- One logical change per commit — resist the urge to bundle unrelated fixes
