---
name: gitmemo
description: Long-term memory for AI agents via local .mem git repo. Interfaces: search, read, write, delete. Use when starting tasks (search past), MUST be used after completing tasks (write), before/after context compression (write then re-read), or when user mentions memory/.mem.
---

# GitMemo — AI Agent Long-Term Memory

Scripts: `scripts/mem.sh` (Linux/macOS) | `scripts/mem.ps1` (Windows). Run from **project root**; auto-locates/creates `.mem` repo.

## Commands

### init
```bash
bash <SKILL_DIR>/scripts/mem.sh init
```

### search
```bash
bash <SKILL_DIR>/scripts/mem.sh search <keywords_csv> [skip] [--mode <and|or|auto>]
```
- `keywords_csv`: comma-separated. `skip`: pagination offset (default 0). Up to 100 results/call, format: `hash|title|date`
- `mode`(default `auto`): `and`=strict, `or`=broad, `auto`=try `and` then fallback `or`

### read
```bash
bash <SKILL_DIR>/scripts/mem.sh read <commit_hash>
```

### write

Single atomic call (create file + git commit):
```bash
bash <SKILL_DIR>/scripts/mem.sh write \
  --title "[module] action + object" \
  --content "<entry_markdown>" \
  --body "<commit_body>"
```
- `--file` optional (defaults to `entries/<timestamp>-<slug>.md`); `--content-file <path>` replaces `--content` for large content
- Auto-syncs `.mem` branch to current repo branch

### delete
```bash
bash <SKILL_DIR>/scripts/mem.sh delete <commit_hash>
```

## Entry Format (--content)

```markdown
---
date: 2026-02-19T15:10:10Z
status: done
repo_branch: main
repo_commit: 9f3e1a2
mem_branch: main
related_paths: [src/auth/login.ts]
tags: [auth, security]
---
### Original User Request
(verbatim)
### AI Understanding
- Goal: / Constraints: / Out of scope:
### Final Outcome
- Changes/outputs summary
```

## Commit Message (--title + --body)

**--title**: `[module] action + object` (e.g. `[auth] add rate-limit for login`)

**--body**: 1-3 sentence summary + metadata (must match front matter):
```
Added per-IP rate limiting (10 req/min) to login endpoint.

date: 2026-02-19T15:10:10Z
tags: auth,security
related-paths: src/auth/login.ts
```

## Workflow

1. **Search**: extract 3-5 keywords → `search` → select top 5 relevant (by keyword overlap, title, recency) → `read` → reuse or reference. Paginate `skip=100` up to 3 batches if needed.
2. **Write**: after completing repo-related task that produced valuable outcome (or user asked to remember) → get UTC time + repo info → build entry → `write`. Skip for: pure Q&A, incomplete tasks, non-repo work.
3. **Delete + rewrite**: if user unsatisfied → `delete` → redo → `write` new memory.
