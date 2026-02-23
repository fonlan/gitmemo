---
name: gitmemo
description: Provide long-term memory for coding AI agents via local git storage. Creates a .mem repository in the project to store task history with search, read, write, and delete interfaces. Use when starting new tasks (to search relevant past memories), after completing tasks (to write memories), before compressing context, or when the user mentions memory, past tasks, conversation history, or .mem.
---

# GitMemo — Long-Term Memory for AI Coding Agents

Stores conversation history and task outcomes in a local `.mem` git repository, enabling AI agents to recall past work.

## Script Interfaces

Choose the script for your OS (paths relative to this skill directory):
- **Linux/macOS**: `scripts/mem.sh`
- **Windows**: `scripts/mem.ps1`

All commands run from the **project root**. The script auto-locates or creates the `.mem` repo.

### init — Initialize

```bash
bash <SKILL_DIR>/scripts/mem.sh init
```

### search — Search Memories

```bash
bash <SKILL_DIR>/scripts/mem.sh search <keywords_csv> [skip] [mode]
# or
bash <SKILL_DIR>/scripts/mem.sh search <keywords_csv> [skip] --mode <and|or|auto>
```

- `keywords_csv`: comma-separated keywords
- `skip`: skip first N results (default 0) for pagination
- `mode`: `and`, `or`, or `auto` (default `auto`)
  - `and`: add `--all-match` for lower noise
  - `or`: keep broad recall
  - `auto`: try `and` first, fallback to `or` if results are too few
- Returns up to 100 results per call, format: `hash|title|date`

### read — Read Memory

```bash
bash <SKILL_DIR>/scripts/mem.sh read <commit_hash>
```

Outputs the full md file content for the given commit.

### commit — Write Memory

Agent creates the md file first, then calls commit:

```bash
# 1. Write md file to .mem/entries/
#    Filename format: <timestamp>-<slug>.md  e.g. 20260219T151010Z-add-auth-rate-limit.md

# 2. Commit
bash <SKILL_DIR>/scripts/mem.sh commit \
  --file "entries/<timestamp>-<slug>.md" \
  --title "[auth] add rate-limit for login endpoint" \
  --body "Added per-IP rate limiting (10 req/min) to the login endpoint
using express-rate-limit, with Redis-backed sliding window.

date: 2026-02-19T15:10:10Z
tags: auth,security
related-paths: src/auth/login.ts,infra/nginx.conf"
```

The script automatically syncs the `.mem` branch to the current code repo branch.

### delete — Delete Memory

```bash
bash <SKILL_DIR>/scripts/mem.sh delete <commit_hash>
```

## Entry File Format

Each entry is an md file with YAML front matter:

```markdown
---
date: 2026-02-19T15:10:10Z
status: done
repo_branch: main
repo_commit: 9f3e1a2
mem_branch: main
related_paths:
  - src/auth/login.ts
  - infra/nginx/nginx.conf
tags:
  - auth
  - security
  - rate-limit
---

### Original User Request
(paste verbatim)

### AI Understanding
- Goal:
- Constraints:
- Out of scope:

### Final Outcome
- Output 1:
- Output 2:
- If code changes: describe change points / API changes
```

## Commit Message Format

**Title**: `[module] action + object + purpose`
- e.g. `[auth] add rate-limit for login endpoint`
- e.g. `[build] fix pnpm lockfile mismatch on CI`

**Body** (AI-generated summary + structured metadata, metadata must stay consistent with md front matter):
```
Added per-IP rate limiting (10 req/min) to the login endpoint using
express-rate-limit, with Redis-backed sliding window and custom 429 response.

date: 2026-02-19T15:10:10Z
tags: auth,security
related-paths: src/auth/login.ts,infra/nginx.conf
```

The first paragraph is a concise summary of the task (what was done and why). Keep it to 1-3 sentences.

## Core Workflow

### On Receiving a User Request — Search Memories

1. Generate 3-5 relevant keywords from the user request
2. Call `search` interface
3. Evaluate whether returned results are relevant
4. If not relevant, paginate with `skip=100` for the next batch (up to 3 batches: skip=0, 100, 200)
5. If relevant memories found, call `read` to get full md content
6. Decide whether the stored conclusion can solve the current problem:
   - **Yes** → return the stored conclusion directly
   - **Partially** → use the memory as reference context and generate a new solution

### After Completing a User Request — Write Memory

**Write conditions** (all must be met):
- Task is complete (not awaiting user reply, not in failed state)
- Task is related to the current code repository
- One of the following is true:
  - Produced a valuable conclusion or change
  - User explicitly asked to remember this request/task

If the user explicitly asks to remember, this overrides the "valuable conclusion or change" requirement, but task completion and repository relevance are still required.

**Do NOT write when**:
- Pure Q&A or casual chat (unless the user explicitly asked to remember)
- Task is still incomplete (awaiting user reply, test failures, etc.)
- Request is unrelated to the current code repository

**Write steps**:
1. Get current UTC timestamp (ISO 8601) and repo info
2. Determine module name, tags, related paths
3. Create the entry md file in `.mem/entries/`
4. Call `commit` interface to commit

### When User Is Unsatisfied — Delete and Rewrite

1. Call `delete` to remove the corresponding memory
2. Redo the task per user feedback
3. Write the new memory

## AGENTS.md Integration

Add the content from [agents-template.md](agents-template.md) to the project's `AGENTS.md` so all AI agents automatically follow the memory workflow.
