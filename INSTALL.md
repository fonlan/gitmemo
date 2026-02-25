# GitMemo Skill Auto-Install (For AI Agents)

Use this document when the user asks an AI coding agent (Copilot/Codex/Claude Code, etc.) to install GitMemo automatically.

Repository: `https://github.com/fonlan/gitmemo.git`

## Install Modes

- `global`: install to `~/.agents/skills/gitmemo`
- `project`: install to `<project_root>/.agents/skills/gitmemo`

## Required Behavior (Agent Contract)

1. Do not ask the user to run commands manually.
2. Execute installation directly and return a short result summary.
3. Make installation idempotent:
- If target exists and is this repo, update it.
- If target exists but is not this repo, backup then reinstall.
4. Verify required files after install:
- `SKILL.md`
- `agents-template.md`
- `scripts/mem.ps1`
- `scripts/mem.sh`
5. Handle instruction-file integration by mode:
- `project` mode must upsert a managed block in `<project_root>/AGENTS.md` using marker lines, replacing the old managed block on upgrades.
- `global` mode defaults to manual-required (do not assume a shared `AGENTS.md` path).
- If the user explicitly requests a target tool (or asks for auto-detect and detection is reliable), `global` mode should upsert `agents-template.md` into that tool's global instruction source.
- If the resolved global target tool is Cursor, write `agents-template.md` into Cursor `.mdc` rule file with required YAML frontmatter and create Cursor skill symlink to the installed gitmemo path.
- If `global` auto-detect is requested but the tool cannot be resolved reliably, return a clear fallback asking for explicit tool type.

## Standard Procedure

1. Resolve target directory by mode.
2. Create parent directories if missing.
3. Install or update:
- If `target/.git` exists and `origin` points to `fonlan/gitmemo`, run `fetch` + `pull --ff-only`.
- Else if target exists, rename target to `*.bak.<timestamp>` and clone fresh.
- Else clone directly.
4. Validate required files exist.
5. For `project` mode, sync `<project_root>/AGENTS.md` with a managed block:
- start marker: `# >>> gitmemo:agents-template:start`
- end marker: `# <<< gitmemo:agents-template:end`
6. Validate project sync result (exactly one marker pair and marker block equals current `agents-template.md`).
7. For `global` mode:
- If tool target is explicit/reliably detected, sync that tool's global instruction source with marker-block upsert semantics and report sync target.
- Otherwise, skip global instruction-file sync and output a manual instruction-file update reminder.
8. Return:
- final install path
- current commit short hash
- instruction integration status (`manual-required` or `synced`)

## Mode: Global Install

Target path:

- Linux/macOS: `~/.agents/skills/gitmemo`
- Windows: `%USERPROFILE%\\.agents\\skills\\gitmemo`
- Instruction integration: manual-required by default; sync is allowed when a specific tool target is requested.

Suggested global instruction targets when explicit tool is requested:

- Codex:
  - Linux/macOS: `~/.codex/AGENTS.md` (or `${CODEX_HOME}/AGENTS.md` if `CODEX_HOME` is set)
  - Windows: `%USERPROFILE%\\.codex\\AGENTS.md` (or `%CODEX_HOME%\\AGENTS.md` if `CODEX_HOME` is set)
- Claude Code:
  - Linux/macOS: `~/.claude/CLAUDE.md`
  - Windows: `%USERPROFILE%\\.claude\\CLAUDE.md`
- Gemini CLI:
  - Linux/macOS: `~/.gemini/GEMINI.md`
  - Windows: `%USERPROFILE%\\.gemini\\GEMINI.md`
- GitHub Copilot (VS Code prompts):
  - Linux: `~/.config/Code/User/prompts/gitmemo.instructions.md`
  - macOS: `~/Library/Application Support/Code/User/prompts/gitmemo.instructions.md`
  - Windows: `%AppData%\\Code\\User\\prompts\\gitmemo.instructions.md`
- Cursor (global rules):
  - Linux/macOS: `~/.cursor/rules/gitmemo.mdc`
  - Windows: `%USERPROFILE%\\.cursor\\rules\\gitmemo.mdc`
  - Note: `.mdc` files require YAML frontmatter before template content:
    ```text
    ---
    description: GitMemo memory workflow
    alwaysApply: true
    ---
    ```
  - Agent Skill symlink (required for Cursor to list `gitmemo` in Agent Skills UI):
    - Linux/macOS: `mkdir -p "$HOME/.cursor/skills" && ln -sfn "$HOME/.agents/skills/gitmemo" "$HOME/.cursor/skills/gitmemo"`
    - Windows: `New-Item -ItemType SymbolicLink -Path "$HOME\\.cursor\\skills\\gitmemo" -Target "$HOME\\.agents\\skills\\gitmemo" -Force`
    - Background: Cursor scans `~/.cursor/skills/*/SKILL.md` for Agent Skills, while gitmemo is stored in `~/.agents/skills/`.

Cursor-specific global sync example (when explicit tool is Cursor):

```bash
cursor_rule="$HOME/.cursor/rules/gitmemo.mdc"
mkdir -p "$(dirname "$cursor_rule")"

cursor_frontmatter=$'---\ndescription: GitMemo memory workflow\nalwaysApply: true\n---\n'
template_content="$(cat "$target/agents-template.md")"
printf "%s%s\n" "$cursor_frontmatter" "$template_content" > "$cursor_rule"

mkdir -p "$HOME/.cursor/skills"
ln -sfn "$target" "$HOME/.cursor/skills/gitmemo"
```

```powershell
$cursorRule = Join-Path $HOME ".cursor/rules/gitmemo.mdc"
New-Item -ItemType Directory -Force -Path (Split-Path $cursorRule -Parent) | Out-Null

$cursorFrontmatter = "---`ndescription: GitMemo memory workflow`nalwaysApply: true`n---`n"
$templateContent = Get-Content (Join-Path $target "agents-template.md") -Raw
Set-Content -Path $cursorRule -Value ($cursorFrontmatter + $templateContent) -NoNewline

$cursorSkillsDir = Join-Path $HOME ".cursor/skills"
New-Item -ItemType Directory -Force -Path $cursorSkillsDir | Out-Null
New-Item -ItemType SymbolicLink -Path (Join-Path $cursorSkillsDir "gitmemo") -Target $target -Force | Out-Null
```

Bash example:

```bash
repo="https://github.com/fonlan/gitmemo.git"
target="$HOME/.agents/skills/gitmemo"
parent="$(dirname "$target")"
mkdir -p "$parent"

origin=""
if [ -d "$target/.git" ]; then
  origin="$(git -C "$target" remote get-url origin 2>/dev/null || true)"
fi

if echo "$origin" | grep -Eq 'github.com[:/]+fonlan/gitmemo(\.git)?$'; then
  git -C "$target" fetch --all --prune
  git -C "$target" pull --ff-only
elif [ -e "$target" ]; then
  ts="$(date -u +%Y%m%d%H%M%S)"
  mv "$target" "${target}.bak.${ts}"
  git clone "$repo" "$target"
else
  git clone "$repo" "$target"
fi

for f in SKILL.md agents-template.md scripts/mem.ps1 scripts/mem.sh; do
  [ -e "$target/$f" ] || { echo "Missing file: $f" >&2; exit 1; }
done

rev="$(git -C "$target" rev-parse --short HEAD)"
manual_note="Manual step required: add $target/agents-template.md to your tool instruction file (for example AGENTS.md, CLAUDE.md, %AppData%\\Code\\User\\prompts\\gitmemo.instructions.md, or ~/.cursor/rules/gitmemo.mdc with required .mdc frontmatter)."
echo "Installed: $target @ $rev | Instruction integration: manual-required | $manual_note"
```

PowerShell example:

```powershell
$repo = "https://github.com/fonlan/gitmemo.git"
$target = Join-Path $HOME ".agents/skills/gitmemo"
$parent = Split-Path $target -Parent
New-Item -ItemType Directory -Force -Path $parent | Out-Null

$origin = ""
if (Test-Path (Join-Path $target ".git")) {
  $origin = (git -C $target remote get-url origin 2>$null)
}

if ($origin -match "github.com[:/]+fonlan/gitmemo(\\.git)?$") {
  git -C $target fetch --all --prune
  git -C $target pull --ff-only
} elseif (Test-Path $target) {
  $ts = Get-Date -Format "yyyyMMddHHmmss"
  Rename-Item -Path $target -NewName ("gitmemo.bak." + $ts)
  git clone $repo $target
} else {
  git clone $repo $target
}

$required = @("SKILL.md","agents-template.md","scripts/mem.ps1","scripts/mem.sh")
$missing = $required | Where-Object { -not (Test-Path (Join-Path $target $_)) }
if ($missing.Count -gt 0) { throw "Missing files: $($missing -join ', ')" }

$rev = git -C $target rev-parse --short HEAD
$manualNote = "Manual step required: add $target/agents-template.md to your tool instruction file (for example AGENTS.md, CLAUDE.md, %AppData%\\Code\\User\\prompts\\gitmemo.instructions.md, or ~/.cursor/rules/gitmemo.mdc with required .mdc frontmatter)."
Write-Output "Installed: $target @ $rev | Instruction integration: manual-required | $manualNote"
```

## Mode: Project Install

Target path:

- `<project_root>/.agents/skills/gitmemo`
- AGENTS file to sync: `<project_root>/AGENTS.md`

Bash example (run from project root):

```bash
repo="https://github.com/fonlan/gitmemo.git"
target="$(pwd)/.agents/skills/gitmemo"
parent="$(dirname "$target")"
mkdir -p "$parent"

origin=""
if [ -d "$target/.git" ]; then
  origin="$(git -C "$target" remote get-url origin 2>/dev/null || true)"
fi

if echo "$origin" | grep -Eq 'github.com[:/]+fonlan/gitmemo(\.git)?$'; then
  git -C "$target" fetch --all --prune
  git -C "$target" pull --ff-only
elif [ -e "$target" ]; then
  ts="$(date -u +%Y%m%d%H%M%S)"
  mv "$target" "${target}.bak.${ts}"
  git clone "$repo" "$target"
else
  git clone "$repo" "$target"
fi

for f in SKILL.md agents-template.md scripts/mem.ps1 scripts/mem.sh; do
  [ -e "$target/$f" ] || { echo "Missing file: $f" >&2; exit 1; }
done

agents_file="$(pwd)/AGENTS.md"
template_file="$target/agents-template.md"
[ -e "$agents_file" ] || { echo "Missing AGENTS.md: $agents_file" >&2; exit 1; }

# Upsert a managed block so reruns replace old template content instead of appending duplicates.
start_marker="# >>> gitmemo:agents-template:start"
end_marker="# <<< gitmemo:agents-template:end"
template_text="$(tr -d '\r' < "$template_file" | sed -e 's/[[:space:]]*$//')"
if echo "$template_text" | grep -Fq "$start_marker" && echo "$template_text" | grep -Fq "$end_marker"; then
  managed_block="$template_text"
else
  managed_block="$start_marker"$'\n'"$template_text"$'\n'"$end_marker"
fi

if grep -Fq "$start_marker" "$agents_file" && grep -Fq "$end_marker" "$agents_file"; then
  sync_action="updated"
  awk -v start="$start_marker" -v end="$end_marker" -v block="$managed_block" '
    BEGIN { in_block=0; replaced=0 }
    $0 == start {
      if (!replaced) { print block; replaced=1 }
      in_block=1
      next
    }
    $0 == end { in_block=0; next }
    !in_block { print }
    END {
      if (!replaced) {
        print ""
        print block
      }
    }
  ' "$agents_file" > "$agents_file.tmp"
else
  sync_action="inserted"
  cp "$agents_file" "$agents_file.tmp"
  printf "\n%s\n" "$managed_block" >> "$agents_file.tmp"
fi
mv "$agents_file.tmp" "$agents_file"

start_count=$(grep -Fxc "$start_marker" "$agents_file" || true)
end_count=$(grep -Fxc "$end_marker" "$agents_file" || true)
[ "$start_count" -eq 1 ] && [ "$end_count" -eq 1 ] || {
  echo "Managed marker count is invalid in $agents_file" >&2
  exit 1
}

block_text="$(awk -v start="$start_marker" -v end="$end_marker" '
  $0 == start { in_block=1 }
  in_block { print }
  $0 == end && in_block { exit }
' "$agents_file" | tr -d '\r' | sed -e 's/[[:space:]]*$//')"
expected_block="$(printf "%s" "$managed_block" | tr -d '\r' | sed -e 's/[[:space:]]*$//')"
[ "$block_text" = "$expected_block" ] || {
  echo "Managed block does not match agents-template.md in $agents_file" >&2
  exit 1
}

rev="$(git -C "$target" rev-parse --short HEAD)"
echo "Installed: $target @ $rev | Instruction integration: synced ($sync_action, $agents_file)"
```

PowerShell example (run from project root):

```powershell
$repo = "https://github.com/fonlan/gitmemo.git"
$target = Join-Path (Get-Location) ".agents/skills/gitmemo"
$parent = Split-Path $target -Parent
New-Item -ItemType Directory -Force -Path $parent | Out-Null

$origin = ""
if (Test-Path (Join-Path $target ".git")) {
  $origin = (git -C $target remote get-url origin 2>$null)
}

if ($origin -match "github.com[:/]+fonlan/gitmemo(\\.git)?$") {
  git -C $target fetch --all --prune
  git -C $target pull --ff-only
} elseif (Test-Path $target) {
  $ts = Get-Date -Format "yyyyMMddHHmmss"
  Rename-Item -Path $target -NewName ("gitmemo.bak." + $ts)
  git clone $repo $target
} else {
  git clone $repo $target
}

$required = @("SKILL.md","agents-template.md","scripts/mem.ps1","scripts/mem.sh")
$missing = $required | Where-Object { -not (Test-Path (Join-Path $target $_)) }
if ($missing.Count -gt 0) { throw "Missing files: $($missing -join ', ')" }

$agentsPath = Join-Path (Get-Location) "AGENTS.md"
if (-not (Test-Path $agentsPath)) { throw "Missing AGENTS.md: $agentsPath" }

$startMarker = "# >>> gitmemo:agents-template:start"
$endMarker = "# <<< gitmemo:agents-template:end"
$templateText = ((Get-Content (Join-Path $target "agents-template.md") -Raw) -replace "`r`n", "`n").Trim()
$hasStartMarker = [regex]::IsMatch($templateText, "(?m)^" + [regex]::Escape($startMarker) + "$")
$hasEndMarker = [regex]::IsMatch($templateText, "(?m)^" + [regex]::Escape($endMarker) + "$")
if ($hasStartMarker -and $hasEndMarker) {
  $managedBlock = $templateText
} else {
  $managedBlock = "$startMarker`n$templateText`n$endMarker"
}

$agentsText = (Get-Content $agentsPath -Raw) -replace "`r`n", "`n"
$pattern = [regex]::Escape($startMarker) + ".*?" + [regex]::Escape($endMarker)

if ($agentsText -match [regex]::Escape($startMarker) -and $agentsText -match [regex]::Escape($endMarker)) {
  $syncAction = "updated"
  $newAgentsText = [regex]::Replace($agentsText, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $managedBlock }, [System.Text.RegularExpressions.RegexOptions]::Singleline)
} else {
  $syncAction = "inserted"
  $newAgentsText = ($agentsText.TrimEnd() + "`n`n" + $managedBlock + "`n")
}

Set-Content -Path $agentsPath -Value $newAgentsText -NoNewline

$saved = (Get-Content $agentsPath -Raw) -replace "`r`n", "`n"
$startCount = [regex]::Matches($saved, [regex]::Escape($startMarker)).Count
$endCount = [regex]::Matches($saved, [regex]::Escape($endMarker)).Count
if ($startCount -ne 1 -or $endCount -ne 1) {
  throw "Managed marker count is invalid in $agentsPath"
}

$blockPattern = [regex]::Escape($startMarker) + ".*?" + [regex]::Escape($endMarker)
$match = [regex]::Match($saved, $blockPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $match.Success) {
  throw "Managed block is missing in $agentsPath"
}
$savedManagedBlock = $match.Value.Trim()
if ($savedManagedBlock -ne $managedBlock) {
  throw "Managed block does not match agents-template.md in $agentsPath"
}

$rev = git -C $target rev-parse --short HEAD
Write-Output "Installed: $target @ $rev | Instruction integration: synced ($syncAction, $agentsPath)"
```

## One-Sentence Prompts (For Users)

- Global install:
`Follow https://github.com/fonlan/gitmemo/blob/main/INSTALL.md and install gitmemo in global mode using OS-specific user home resolution (~/.agents/skills/gitmemo on Linux/macOS, %USERPROFILE%\\.agents\\skills\\gitmemo on Windows); then auto-detect the current coding agent (codex/claude code/gemini cli/copilot/cursor) and upsert agents-template.md into that tool's global instruction source, or ask for explicit tool type if detection is not reliable; if tool is Cursor, write ~/.cursor/rules/gitmemo.mdc with required YAML frontmatter and create ~/.cursor/skills/gitmemo symlink to ~/.agents/skills/gitmemo; report path, commit, integration status, and instruction target.`

- Project install:
`Follow https://github.com/fonlan/gitmemo/blob/main/INSTALL.md and install gitmemo to .agents/skills/gitmemo in the current project in project mode, sync AGENTS.md using the managed marker block, and report path, commit, and instruction integration sync result.`
