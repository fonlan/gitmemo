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
5. Verify AGENTS template integration:
- `global` mode must check `~/.agents/AGENTS.md`
- `project` mode must check `<project_root>/AGENTS.md`
- The target `AGENTS.md` must contain the content of `agents-template.md`

## Standard Procedure

1. Resolve target directory by mode.
2. Create parent directories if missing.
3. Install or update:
- If `target/.git` exists and `origin` points to `fonlan/gitmemo`, run `fetch` + `pull --ff-only`.
- Else if target exists, rename target to `*.bak.<timestamp>` and clone fresh.
- Else clone directly.
4. Validate required files exist.
5. Validate that the mode-specific `AGENTS.md` contains `agents-template.md` content.
6. Return:
- final install path
- current commit short hash
- AGENTS check result

## Mode: Global Install

Target path:

- Linux/macOS: `~/.agents/skills/gitmemo`
- Windows: `%USERPROFILE%\\.agents\\skills\\gitmemo`
- AGENTS file to validate: `~/.agents/AGENTS.md`

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

agents_file="$HOME/.agents/AGENTS.md"
template_file="$target/agents-template.md"
[ -e "$agents_file" ] || { echo "Missing AGENTS.md: $agents_file" >&2; exit 1; }

# Normalize CRLF and ensure AGENTS.md contains the full template text.
template_text="$(tr -d '\r' < "$template_file")"
agents_text="$(tr -d '\r' < "$agents_file")"
if ! awk -v txt="$agents_text" -v tmpl="$template_text" 'BEGIN { exit(index(txt, tmpl) ? 0 : 1) }'; then
  echo "AGENTS.md does not contain agents-template.md content: $agents_file" >&2
  exit 1
fi

rev="$(git -C "$target" rev-parse --short HEAD)"
echo "Installed: $target @ $rev | AGENTS check: pass ($agents_file)"
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

$agentsPath = Join-Path $HOME ".agents/AGENTS.md"
if (-not (Test-Path $agentsPath)) { throw "Missing AGENTS.md: $agentsPath" }

$templateText = ((Get-Content (Join-Path $target "agents-template.md") -Raw) -replace "`r`n", "`n").Trim()
$agentsText = ((Get-Content $agentsPath -Raw) -replace "`r`n", "`n")
if (-not $agentsText.Contains($templateText)) {
  throw "AGENTS.md does not contain agents-template.md content: $agentsPath"
}

$rev = git -C $target rev-parse --short HEAD
Write-Output "Installed: $target @ $rev | AGENTS check: pass ($agentsPath)"
```

## Mode: Project Install

Target path:

- `<project_root>/.agents/skills/gitmemo`
- AGENTS file to validate: `<project_root>/AGENTS.md`

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

# Normalize CRLF and ensure AGENTS.md contains the full template text.
template_text="$(tr -d '\r' < "$template_file")"
agents_text="$(tr -d '\r' < "$agents_file")"
if ! awk -v txt="$agents_text" -v tmpl="$template_text" 'BEGIN { exit(index(txt, tmpl) ? 0 : 1) }'; then
  echo "AGENTS.md does not contain agents-template.md content: $agents_file" >&2
  exit 1
fi

rev="$(git -C "$target" rev-parse --short HEAD)"
echo "Installed: $target @ $rev | AGENTS check: pass ($agents_file)"
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

$templateText = ((Get-Content (Join-Path $target "agents-template.md") -Raw) -replace "`r`n", "`n").Trim()
$agentsText = ((Get-Content $agentsPath -Raw) -replace "`r`n", "`n")
if (-not $agentsText.Contains($templateText)) {
  throw "AGENTS.md does not contain agents-template.md content: $agentsPath"
}

$rev = git -C $target rev-parse --short HEAD
Write-Output "Installed: $target @ $rev | AGENTS check: pass ($agentsPath)"
```

## One-Sentence Prompts (For Users)

- Global install:
`Follow https://github.com/fonlan/gitmemo/blob/main/INSTALL.md and install gitmemo to ~/.agents/skills/gitmemo in global mode, then verify ~/.agents/AGENTS.md contains agents-template.md content and report path, commit, and AGENTS check result.`

- Project install:
`Follow https://github.com/fonlan/gitmemo/blob/main/INSTALL.md and install gitmemo to .agents/skills/gitmemo in the current project in project mode, then verify ./AGENTS.md contains agents-template.md content and report path, commit, and AGENTS check result.`
