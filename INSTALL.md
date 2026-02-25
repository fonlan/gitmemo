# GitMemo Skill — Auto-Install Contract (For AI Agents)

This document is the execution contract for AI coding agents. Follow it precisely when the user asks to install GitMemo.

Repository: `https://github.com/fonlan/gitmemo.git`

---

## 1. Meta

| Mode | Target Path (Linux/macOS) | Target Path (Windows) |
|------|---------------------------|------------------------|
| `global` | `~/.agents/skills/gitmemo` | `%USERPROFILE%\.agents\skills\gitmemo` |
| `project` | `<project_root>/.agents/skills/gitmemo` | `<project_root>\.agents\skills\gitmemo` |

Required files (must exist after install): `SKILL.md`, `agents-template.md`, `scripts/mem.ps1`, `scripts/mem.sh`

---

## 2. Agent Contract

1. **Execute directly** — do not ask the user to run commands manually.
2. **Return a short result summary** on completion.
3. **Idempotent**:
   - Target exists and is this repo → update (`fetch` + `pull --ff-only`).
   - Target exists but is a different repo → backup (`*.bak.<timestamp>`) + clone fresh.
   - Target does not exist → clone directly.
4. **Validate** required files after install.
5. **Instruction-file integration** (see Step 4 below for details):
   - `project` mode → upsert managed block into `<project_root>/AGENTS.md`.
   - `global` mode → default `manual-required`; sync only when the user provides an explicit tool target or requests auto-detect and detection is reliable.
   - If `global` auto-detect cannot resolve the tool reliably → ask the user for explicit tool type.
6. **Report**: installed path, commit short hash, instruction integration status (`manual-required` | `synced`).

---

## 3. Standard Procedure

### Step 1 — Resolve Target Directory

- `global`: OS-specific home path per the table in §1.
- `project`: `<project_root>/.agents/skills/gitmemo`.
- Create parent directories if missing.

### Step 2 — Install or Update

```text
if target/.git exists AND remote origin matches fonlan/gitmemo:
    git -C <target> fetch --all --prune
    git -C <target> pull --ff-only
else if target exists:
    rename target → <target>.bak.<UTC_timestamp>
    git clone <repo> <target>
else:
    git clone <repo> <target>
```

Origin match pattern: `github.com[:/]+fonlan/gitmemo(\.git)?$`

### Step 3 — Validate Required Files

Check that `SKILL.md`, `agents-template.md`, `scripts/mem.ps1`, `scripts/mem.sh` all exist under `<target>`. Abort on any missing file.

### Step 4 — Instruction Integration

#### 4a. Project Mode — Sync `<project_root>/AGENTS.md`

Managed-block markers:

- Start: `# >>> gitmemo:agents-template:start`
- End: `# <<< gitmemo:agents-template:end`

Upsert logic:

```text
read agents-template.md content
if template already contains both markers:
    managed_block = template content as-is
else:
    managed_block = start_marker + "\n" + template content + "\n" + end_marker

if AGENTS.md contains both markers:
    replace everything between (and including) markers with managed_block  → "updated"
else:
    append managed_block to end of AGENTS.md  → "inserted"
```

Post-sync validation:

- Exactly **one** start marker and **one** end marker exist in the file.
- The block between markers equals `managed_block` verbatim.

#### 4b. Global Mode — Tool-Specific Instruction Integration

Default behavior: **`manual-required`** (skip sync, output a reminder listing possible instruction file targets).

When a specific tool is provided or reliably detected, upsert `agents-template.md` into that tool's global instruction file using the same managed-block marker semantics as project mode.

**Global instruction file paths by tool:**

| Tool | Linux | macOS | Windows |
|------|-------|-------|---------|
| Codex | `~/.codex/AGENTS.md` | `~/.codex/AGENTS.md` | `%USERPROFILE%\.codex\AGENTS.md` |
| Claude Code | `~/.claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | `%USERPROFILE%\.claude\CLAUDE.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` | `~/.gemini/GEMINI.md` | `%USERPROFILE%\.gemini\GEMINI.md` |
| GitHub Copilot | `~/.config/Code/User/prompts/gitmemo.instructions.md` | `~/Library/Application Support/Code/User/prompts/gitmemo.instructions.md` | `%AppData%\Code\User\prompts\gitmemo.instructions.md` |
| Cursor | `~/.cursor/rules/gitmemo.mdc` | `~/.cursor/rules/gitmemo.mdc` | `%USERPROFILE%\.cursor\rules\gitmemo.mdc` |

> Note: Codex also respects `$CODEX_HOME/AGENTS.md` / `%CODEX_HOME%\AGENTS.md` if the env var is set.

**GitHub Copilot-specific extra steps** (required when target tool is GitHub Copilot):

1. **YAML frontmatter** — The instructions file must start with the following frontmatter, followed by `agents-template.md` content:
   ```yaml
   ---
   applyTo: '**'
   ---
   ```

**Cursor-specific extra steps** (required when target tool is Cursor):

1. **`.mdc` YAML frontmatter** — The rule file must start with the following frontmatter, followed by `agents-template.md` content:
   ```yaml
   ---
   description: GitMemo memory workflow
   alwaysApply: true
   ---
   ```
2. **Agent Skill link** — Cursor scans `~/.cursor/skills/*/SKILL.md` for Agent Skills. Link `~/.cursor/skills/gitmemo` → `<installed_path>`:
   - Linux/macOS: `ln -sfn <installed_path> ~/.cursor/skills/gitmemo`
   - Windows (use directory junction to avoid admin requirement): `cmd /c mklink /J "%USERPROFILE%\.cursor\skills\gitmemo" "<installed_path>"`

### Step 5 — Report Result

Output format:

```text
Installed: <path> @ <commit_short_hash> | Instruction integration: <status> [(<action>, <target_file>)]
```

- `<status>`: `manual-required` or `synced`
- `<action>` (only when synced): `inserted` or `updated`
- `<target_file>` (only when synced): path of the instruction file that was modified

If `manual-required`, append a reminder: _"Add `<target>/agents-template.md` contents to your tool's instruction file (e.g. AGENTS.md, CLAUDE.md, gitmemo.instructions.md, or gitmemo.mdc with YAML frontmatter)."_
