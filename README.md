[Chinese Version (README_CN.md)](./README_CN.md)

# GitMemo Skill

A lightweight skill that gives coding agents long-term memory through a **local** `.mem` Git repository. Git is the only dependency.

## Overview

- Stores completed task outcomes as markdown entries under `.mem/entries/`
- Provides memory operations: `init`, `search`, `read`, `commit`, `delete`
- Aligns the `.mem` branch with the current project branch on commit
- Integrates with `AGENTS.md` so all agents follow the same memory policy

## File Layout

- `SKILL.md`: skill definition and workflow rules
- `agents-template.md`: snippet to append to project `AGENTS.md`
- `scripts/mem.ps1`: Windows interface
- `scripts/mem.sh`: Linux/macOS interface

## Quick Start

Run commands from the project root (not inside `.mem`).

### Windows (PowerShell)

```powershell
./scripts/mem.ps1 init
./scripts/mem.ps1 search "auth,rate-limit" 0
./scripts/mem.ps1 read <commit_hash>
./scripts/mem.ps1 commit --file "entries/<timestamp>-<slug>.md" --title "[module] action object purpose" --body "summary..."
./scripts/mem.ps1 delete <commit_hash>
```

### Linux/macOS (Bash)

```bash
bash ./scripts/mem.sh init
bash ./scripts/mem.sh search "auth,rate-limit" 0
bash ./scripts/mem.sh read <commit_hash>
bash ./scripts/mem.sh commit --file "entries/<timestamp>-<slug>.md" --title "[module] action object purpose" --body "summary..."
bash ./scripts/mem.sh delete <commit_hash>
```

## Agent Workflow

### 1. Before Work: Search

1. Extract 3-5 keywords from the user request.
2. Run `search` with `skip=0`.
3. If not relevant, paginate with `skip=100` and `skip=200`.
4. If relevant memories exist, run `read` and reuse conclusions when appropriate.

### 2. After Completion: Write

Write memory only when all are true:

- Task is complete
- Task is related to the current repository
- Outcome is valuable and reusable

Do not write memory for casual chat, pure Q&A, or incomplete tasks.

### 3. If User Is Unsatisfied: Delete and Rewrite

1. Run `delete <commit_hash>`
2. Redo the task based on feedback
3. Write a corrected memory entry

## Entry Format

Each memory entry is a markdown file in `.mem/entries/` with YAML front matter:

```md
---
date: 2026-02-19T15:10:10Z
status: done
repo_branch: main
repo_commit: 9f3e1a2
mem_branch: main
related_paths:
  - src/auth/login.ts
tags:
  - auth
  - security
---

### Original User Request
(verbatim)

### AI Understanding
- Goal:
- Constraints:
- Out of scope:

### Final Outcome
- Output 1:
```

Filename convention:

- `<timestamp>-<slug>.md` (example: `20260219T151010Z-add-auth-rate-limit.md`)

## Commit Message Convention

- Title: `[module] action + object + purpose`
- Body includes a 1-3 sentence summary
- Body includes metadata lines: `date`, `tags`, `related-paths`

## AGENTS.md Integration

Copy the content from `agents-template.md` into your repository `AGENTS.md` so all agents follow the GitMemo memory workflow by default.
