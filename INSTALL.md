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
- `global` mode must not auto-update or validate a shared `AGENTS.md` path.
- `global` mode must return a manual next step for the user to update their tool instruction file.

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
7. For `global` mode, skip AGENTS validation and output a manual instruction-file update reminder.
8. Return:
- final install path
- current commit short hash
- instruction integration status (`manual-required` for global, `synced` for project)

## Mode: Global Install

Target path:

- Linux/macOS: `~/.agents/skills/gitmemo`
- Windows: `%USERPROFILE%\\.agents\\skills\\gitmemo`
- Instruction integration: manual update required in global mode

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
manual_note="Manual step required: add $target/agents-template.md to your tool instruction file (for example AGENTS.md, CLAUDE.md, or .github/copilot-instructions.md)."
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
$manualNote = "Manual step required: add $target/agents-template.md to your tool instruction file (for example AGENTS.md, CLAUDE.md, or .github/copilot-instructions.md)."
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
`Follow https://github.com/fonlan/gitmemo/blob/main/INSTALL.md and install gitmemo in global mode, do not validate or update a shared AGENTS.md path, and report installed path, commit, and a manual next step for instruction-file update using agents-template.md.`

- Project install:
`Follow https://github.com/fonlan/gitmemo/blob/main/INSTALL.md and install gitmemo to .agents/skills/gitmemo in the current project in project mode, sync AGENTS.md using the managed marker block, and report path, commit, and instruction integration sync result.`
