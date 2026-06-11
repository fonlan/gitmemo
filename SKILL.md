---
name: gitmemo
description: "Long-term memory for AI agents via local .mem git repo. Interfaces: search, read, write, delete. MUST be used when starting tasks (search past), after completing tasks (write), before/after context compression (write then re-read), or when user mentions memory/.mem."
---

# GitMemo — AI Agent Long-Term Memory

Scripts: `<SKILL_DIR>/scripts/mem.sh` (Linux/macOS) | `<SKILL_DIR>/scripts/mem.ps1` (Windows).
There is no required standalone `gitmemo` executable; always invoke `mem.sh` / `mem.ps1` by path.

Path semantics:
- Script lookup: always resolve `mem.sh`/`mem.ps1` from the **skill installation directory** (`<SKILL_DIR>/scripts`), not from the current project directory. This supports global skill installation.
- Memory repo location: `.mem` is always in the **current project root** (working directory), and is auto-located/created there.

## Commands

### Argument Contract

- `--mode` is valid only for `search`. Do not append `--mode` to `read`, `write`, or `delete`.
- `write` has two separate payloads:
  - memory entry Markdown: required; provide exactly one of `--content-file <path>`, `--content <markdown>`, or an existing `.mem/entries/...` file via `--file <entry_path>`.
  - commit body: optional; provide `--body-file <path>` or short single-line `--body "<text>"`.
- `--body` is never memory content. A command like `write --title T --body $'---\n...'` is missing entry content and must fail.

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
- Exact interface: `read <commit_hash>` only. No `--mode`.

### write

Exact interface:
```bash
bash <SKILL_DIR>/scripts/mem.sh write --title <title> [--file <entry_path>] [--content-file <path> | --content <markdown>] [--body-file <path> | --body <text>]
```
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>/scripts/mem.ps1" write --title <title> [--file <entry_path>] [--content-file <path> | --content <markdown>] [--body-file <path> | --body <text>]
```

Do not improvise flags:
```bash
# Wrong: --mode is search-only, and --body is only the optional commit body.
bash <SKILL_DIR>/scripts/mem.sh write --title "[module] done" --body $'---\n...' --mode auto

# Right: entry Markdown goes through --content-file; commit body goes through --body-file.
bash <SKILL_DIR>/scripts/mem.sh write --title "[module] done" --content-file "<entry_md_path>" --body-file "<body_txt_path>"
```

**Preferred path — use the IDE/agent native file-write tool (Cursor `Write`, VSCode Copilot `Create/Edit File`, Claude Code `Write`, etc.)**

Authoring Markdown directly with the IDE's file-write tool sidesteps all PowerShell/bash heredoc, quoting, escaping and code-page pitfalls. The mem scripts are designed to commit a pre-written file in place:

1. Pick an entry filename `entries/<YYYYMMDDTHHMMSSZ>-<slug>.md`. Use the IDE's file-write tool to create `.mem/entries/<filename>` with the full memory Markdown (UTF-8, no BOM — IDE tools default to this).
2. Use the same IDE tool to write the optional commit body text to a temp file (e.g. `<TEMP>/gitmemo-<uuid>.body.txt`). Skip this step and omit commit body entirely, or use `--body "<one line>"` only if the body is a single short line.
3. Commit via `mem.sh` / `mem.ps1`:

```bash
bash <SKILL_DIR>/scripts/mem.sh write \
  --title "[module] action + object" \
  --content-file ".mem/entries/<filename>" \
  --body-file "<temp_body_path>"
```
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>/scripts/mem.ps1" write `
  --title "[module] action + object" `
  --content-file ".mem/entries/<filename>" `
  --body-file "<temp_body_path>"
```

When `--content-file` already lives under `.mem/entries`, the script reuses it in place (no copy, file is kept) and auto-syncs the `.mem` branch to the current repo branch. `--file entries/<filename>` is an equivalent form once the file is on disk.

**Fallback — shell heredoc when no IDE write tool is available**

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

On Windows PowerShell, heredoc-style here-strings are fragile (quoting, backtick escapes, ANSI/UTF-8 code page mismatches) and frequently corrupt CJK or special characters. **Strongly prefer the IDE write path above.** If you must use PowerShell, write the files via `[System.IO.File]::WriteAllText(...)` with `UTF8Encoding($false)` and treat any write failure as a signal to fall back to the IDE path rather than retrying.

- Keep only the short title in the command line. Do not pass multiline Markdown or commit bodies through `--content` / `--body`; always go through `--content-file` / `--body-file`.
- `--content` / `--body` stay as compatibility-only flags for short, single-line values.
- Temp files passed via `--content-file` are auto-deleted after a successful write; files that already live under `.mem/entries` are committed in place and kept.
- `--file` accepts `entries/foo.md`, `.mem/entries/foo.md`, and absolute paths under `.mem/entries`, and commits existing entry files directly.

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
