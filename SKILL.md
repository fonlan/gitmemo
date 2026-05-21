---
name: gitmemo
description: "Long-term memory for AI agents via local .mem git repo. Interfaces: search, read, write, delete. MUST be used when starting tasks (search past), after completing tasks (write), before/after context compression (write then re-read), or when user mentions memory/.mem."
---

# GitMemo — AI Agent Long-Term Memory

Scripts: `<SKILL_DIR>/scripts/mem.sh` (Linux/macOS) | `<SKILL_DIR>/scripts/mem.ps1` (Windows).

Path semantics:
- Script lookup: always resolve `mem.sh`/`mem.ps1` from the **skill installation directory** (`<SKILL_DIR>/scripts`), not from the current project directory. This supports global skill installation.
- Memory repo location: `.mem` is always in the **current project root** (working directory), and is auto-located/created there.

## Commands

### init
```bash
bash <SKILL_DIR>/scripts/mem.sh init
```
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>/scripts/mem.ps1" init
```

### search
```bash
bash <SKILL_DIR>/scripts/mem.sh search <keywords_csv> [skip] [--mode <and|or|auto>]
```
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>/scripts/mem.ps1" search <keywords_csv> [skip] [--mode <and|or|auto>]
```
- `keywords_csv`: comma-separated. `skip`: pagination offset (default 0). Up to 20 results/call, format: `hash|title|date`
- `mode` (default `auto`): `and`=strict, `or`=broad, `auto`=try `and` then fallback `or`

### read
```bash
bash <SKILL_DIR>/scripts/mem.sh read <commit_hash>
```
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>/scripts/mem.ps1" read <commit_hash>
```

### write

Preferred pattern: write Markdown + commit body to temp files, then pass `--content-file` + `--body-file`.

~~~bash
tmp_md="$(mktemp)"
tmp_body="$(mktemp)"
cat > "$tmp_md" <<'MD'
<entry_markdown>
MD
cat > "$tmp_body" <<'BODY'
<commit_body>
BODY
bash <SKILL_DIR>/scripts/mem.sh write \
  --title "[module] action + object" \
  --content-file "$tmp_md" \
  --body-file "$tmp_body"
~~~
~~~powershell
$tmpMd = Join-Path $env:TEMP ("gitmemo-" + [guid]::NewGuid().ToString() + ".md")
$tmpBody = Join-Path $env:TEMP ("gitmemo-" + [guid]::NewGuid().ToString() + ".body.txt")
[System.IO.File]::WriteAllText($tmpMd, @'
<entry_markdown>
'@, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($tmpBody, @'
<commit_body>
'@, [System.Text.UTF8Encoding]::new($false))
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>/scripts/mem.ps1" write `
  --title "[module] action + object" `
  --content-file $tmpMd `
  --body-file $tmpBody
~~~

- Keep only the short title in the command line. Do not pass multiline Markdown or commit bodies through `--content` / `--body`; write files with UTF-8 no BOM and pass `--content-file` / `--body-file`.
- `--content` / `--body` stay as compatibility-only flags for short, single-line values.
- Temp files passed via `--content-file` are auto-deleted after a successful write.
- `--file` is optional, accepts `entries/foo.md`, `.mem/entries/foo.md`, and absolute paths under `.mem/entries`, and commits existing entry files directly.
- If `--content-file` already points inside `.mem/entries`, write reuses it in place and auto-syncs the `.mem` branch to the current repo branch.

### delete
```bash
bash <SKILL_DIR>/scripts/mem.sh delete <commit_hash>
```
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>/scripts/mem.ps1" delete <commit_hash>
```

## Entry Format (--content-file)

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

## Commit Message (--title + --body-file)

**--title**: `[module] action + object` (e.g. `[auth] add rate-limit for login`)

**--body-file**: 1-3 sentence summary + metadata (must match front matter):
```
Added per-IP rate limiting (10 req/min) to login endpoint.

date: 2026-02-19T15:10:10Z
tags: auth,security
related-paths: src/auth/login.ts
```

## Workflow

1. **Search**: extract 3-5 keywords → `search` → select top 5 relevant (by keyword overlap, title, recency) → `read` → reuse or reference. Paginate with `skip=20`, then `skip=40` (and continue by +20 if needed).
2. **Write**: after completing repo-related task that produced valuable outcome (or user asked to remember) → get UTC time + repo info → build entry → `write`. Skip for: pure Q&A, incomplete tasks, non-repo work.
  Also skip for purely operational git actions (e.g., commit/push only) that do not produce a new implementation or analysis outcome.
3. **Delete + rewrite**: if user unsatisfied → `delete` → redo → `write` new memory.
