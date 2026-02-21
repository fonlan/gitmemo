#Requires -Version 5.1
param(
    [Parameter(Position=0)]
    [string]$Command,
    [Parameter(Position=1, ValueFromRemainingArguments)]
    [string[]]$Args
)

$ErrorActionPreference = "Stop"

function Find-RepoRoot {
    $root = git rev-parse --show-toplevel 2>$null
    if ($root) { return $root }
    return (Get-Location).Path
}

function Resolve-MemDir {
    $root = Find-RepoRoot
    return Join-Path $root ".mem"
}

function Ensure-Init {
    $script:MemDir = Resolve-MemDir
    if (-not (Test-Path (Join-Path $script:MemDir ".git"))) {
        $entries = Join-Path $script:MemDir "entries"
        New-Item -ItemType Directory -Path $entries -Force | Out-Null
        git -C $script:MemDir init -q
        New-Item -ItemType File -Path (Join-Path $entries ".gitkeep") -Force | Out-Null
        git -C $script:MemDir add .
        git -C $script:MemDir commit -q -m "init: initialize memory repo"
    }
}

function Get-SafeBranch {
    param([string]$Dir)
    $branch = git -C $Dir rev-parse --abbrev-ref HEAD 2>$null
    if (-not $branch -or $branch -eq "HEAD") { return "main" }
    return $branch
}

function Sync-Branch {
    $root = Find-RepoRoot
    $repoBranch = Get-SafeBranch -Dir $root
    $memBranch = Get-SafeBranch -Dir $script:MemDir

    if ($memBranch -ne $repoBranch) {
        $exists = git -C $script:MemDir show-ref --verify --quiet "refs/heads/$repoBranch" 2>$null
        if ($LASTEXITCODE -eq 0) {
            git -C $script:MemDir checkout -q $repoBranch
        } else {
            git -C $script:MemDir checkout -q -b $repoBranch
        }
    }
    return $repoBranch
}

function Invoke-Init {
    Ensure-Init
    Write-Output "OK: Memory repo initialized at $script:MemDir"
}

function Invoke-Search {
    param([string]$Keywords, [int]$Skip = 0)
    Ensure-Init

    if (-not $Keywords) {
        Write-Error "Usage: mem.ps1 search <keywords_csv> [skip]"
        return
    }

    $grepArgs = @()
    foreach ($kw in ($Keywords -split ',')) {
        $kw = $kw.Trim()
        if ($kw) { $grepArgs += "--grep=$kw" }
    }

    if ($grepArgs.Count -eq 0) {
        Write-Error "Error: no valid keywords"
        return
    }

    $gitArgs = @("log") + $grepArgs + @(
        "-i", "--skip=$Skip", "--max-count=100",
        "--format=%H|%s|%cd", "--date=iso", "--all"
    )
    & git -C $script:MemDir @gitArgs 2>$null
}

function Invoke-Read {
    param([string]$CommitHash)
    Ensure-Init

    if (-not $CommitHash) {
        Write-Error "Usage: mem.ps1 read <commit_hash>"
        return
    }

    $file = git -C $script:MemDir diff-tree --no-commit-id --name-only -r $CommitHash -- entries/ 2>$null | Select-Object -First 1
    if (-not $file) {
        $file = git -C $script:MemDir diff-tree --root --no-commit-id --name-only -r $CommitHash -- entries/ 2>$null | Select-Object -First 1
    }

    if ($file) {
        git -C $script:MemDir show "${CommitHash}:${file}" 2>$null
    } else {
        Write-Error "Error: no entry file found in commit $CommitHash"
    }
}

function Invoke-Commit {
    param([string[]]$Params)
    Ensure-Init

    $file = ""; $title = ""; $body = ""
    for ($i = 0; $i -lt $Params.Count; $i++) {
        switch ($Params[$i]) {
            "--file"  { $file  = $Params[++$i] }
            "--title" { $title = $Params[++$i] }
            "--body"  { $body  = $Params[++$i] }
            default   { Write-Error "Unknown option: $($Params[$i])"; return }
        }
    }

    if (-not $file -or -not $title) {
        Write-Error "Usage: mem.ps1 commit --file <path> --title <title> [--body <body>]"
        return
    }

    $fullPath = Join-Path $script:MemDir $file
    if (-not (Test-Path $fullPath)) {
        Write-Error "Error: file not found: $fullPath"
        return
    }

    Sync-Branch | Out-Null

    git -C $script:MemDir add $file
    if ($body) {
        git -C $script:MemDir commit -q -m $title -m $body
    } else {
        git -C $script:MemDir commit -q -m $title
    }

    $hash = git -C $script:MemDir rev-parse HEAD
    Write-Output "OK: $hash"
}

function Invoke-Delete {
    param([string]$CommitHash)
    Ensure-Init

    if (-not $CommitHash) {
        Write-Error "Usage: mem.ps1 delete <commit_hash>"
        return
    }

    $file = git -C $script:MemDir diff-tree --no-commit-id --name-only -r $CommitHash -- entries/ 2>$null | Select-Object -First 1
    if (-not $file) {
        $file = git -C $script:MemDir diff-tree --root --no-commit-id --name-only -r $CommitHash -- entries/ 2>$null | Select-Object -First 1
    }

    if (-not $file) {
        Write-Error "Error: no entry file found in commit $CommitHash"
        return
    }

    $fullPath = Join-Path $script:MemDir $file
    if (Test-Path $fullPath) {
        git -C $script:MemDir rm -q $file
        $basename = [System.IO.Path]::GetFileNameWithoutExtension($file)
        git -C $script:MemDir commit -q -m "delete: remove $basename"
        Write-Output "OK: deleted $file"
    } else {
        Write-Error "Error: file already deleted: $file"
    }
}

switch ($Command) {
    "init"   { Invoke-Init }
    "search" {
        $kw = if ($Args.Count -ge 1) { $Args[0] } else { "" }
        $sk = if ($Args.Count -ge 2) { [int]$Args[1] } else { 0 }
        Invoke-Search -Keywords $kw -Skip $sk
    }
    "read"   { Invoke-Read -CommitHash ($Args | Select-Object -First 1) }
    "commit" { Invoke-Commit -Params $Args }
    "delete" { Invoke-Delete -CommitHash ($Args | Select-Object -First 1) }
    default  {
        Write-Host "Usage: mem.ps1 {init|search|read|commit|delete}"
        Write-Host "  init                                    Initialize .mem repo"
        Write-Host "  search <keywords_csv> [skip]            Search memories"
        Write-Host "  read <commit_hash>                      Read memory content"
        Write-Host "  commit --file F --title T [--body B]    Commit memory entry"
        Write-Host "  delete <commit_hash>                    Delete memory entry"
    }
}
