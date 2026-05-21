#Requires -Version 5.1

# Parse positional CLI arguments manually to avoid binding side effects with automatic variables.
$Command = if ($args.Count -gt 0) { [string]$args[0] } else { "" }
$RemainingParameters = if ($args.Count -gt 1) { @($args[1..($args.Count - 1)]) } else { @() }

$ErrorActionPreference = "Stop"

# Force UTF-8 (no BOM) for console I/O and pipe encoding so that:
# - reading native command stdout (e.g. git show) decodes UTF-8 bytes correctly instead of via the system ANSI code page
# - writing to stdout emits UTF-8 bytes that downstream tools can read losslessly
# - text piped to native commands is sent as UTF-8
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
try { [Console]::OutputEncoding = $script:Utf8NoBom } catch { }
try { [Console]::InputEncoding = $script:Utf8NoBom } catch { }
$OutputEncoding = $script:Utf8NoBom

$script:RepoRoot = $null
$script:MemDir = $null

function Find-RepoRoot {
    if ($script:RepoRoot) { return $script:RepoRoot }

    $root = $null
    try {
        $resolved = & git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $resolved) {
            $root = ($resolved | Select-Object -First 1).Trim()
        }
    }
    catch {
        $root = $null
    }
    if (-not $root) {
        $root = (Get-Location).Path
    }

    $script:RepoRoot = $root
    return $script:RepoRoot
}

function Resolve-MemDir {
    if ($script:MemDir) { return $script:MemDir }

    $script:MemDir = Join-Path (Find-RepoRoot) ".mem"
    return $script:MemDir
}

function Normalize-EntryLikePath {
    param([string]$Path)
    if (-not $Path) { return "" }
    $normalized = $Path -replace "\\", "/"
    if ($normalized.StartsWith("./")) {
        $normalized = $normalized.Substring(2)
    }
    return $normalized
}

function Initialize-MemoryRepo {
    $script:MemDir = Resolve-MemDir
    if (-not (Test-Path -LiteralPath (Join-Path $script:MemDir ".git") -PathType Container)) {
        $entries = Join-Path $script:MemDir "entries"
        New-Item -ItemType Directory -Path $entries -Force | Out-Null
        git -C $script:MemDir init -q
        New-Item -ItemType File -Path (Join-Path $entries ".gitkeep") -Force | Out-Null
        git -C $script:MemDir add "entries/.gitkeep"
        git -C $script:MemDir commit -q -m "init: initialize memory repo"
    }
}

function Get-SafeBranch {
    param([string]$Dir)
    $branch = $null
    try {
        $resolved = & git -C $Dir rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $resolved) {
            $branch = ($resolved | Select-Object -First 1).Trim()
        }
    }
    catch {
        $branch = $null
    }
    if (-not $branch -or $branch -eq "HEAD") { return "main" }
    return $branch
}

function Sync-Branch {
    $root = Find-RepoRoot
    $repoBranch = Get-SafeBranch -Dir $root
    $memBranch = Get-SafeBranch -Dir $script:MemDir

    if ($memBranch -ne $repoBranch) {
        git -C $script:MemDir show-ref --verify --quiet "refs/heads/$repoBranch" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            git -C $script:MemDir checkout -q $repoBranch
        }
        else {
            git -C $script:MemDir checkout -q -b $repoBranch
        }
    }
    return $repoBranch
}

function Resolve-EntryPath {
    param([string]$File)
    if (-not $File) { return $File }
    $directEntry = Get-DirectEntryPath -Path $File
    if ($directEntry) { return $directEntry }

    $normalized = Normalize-EntryLikePath -Path $File
    if (-not $normalized) { return $normalized }
    return "entries/$normalized"
}

function Get-DirectEntryPath {
    param([string]$Path)
    if (-not $Path) { return "" }

    $normalized = Normalize-EntryLikePath -Path $Path
    if ($normalized -like ".mem/entries/*") {
        return $normalized.Substring(5)
    }
    if ($normalized -like "entries/*") {
        return $normalized
    }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        $memPrefix = [System.IO.Path]::GetFullPath($script:MemDir).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        $entriesPrefix = [System.IO.Path]::GetFullPath((Join-Path $script:MemDir "entries")).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        if ($fullPath.StartsWith($entriesPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relative = $fullPath.Substring($memPrefix.Length)
            return (Normalize-EntryLikePath -Path $relative)
        }
    }
    catch {
        return ""
    }

    return ""
}

function Test-SafeEntryPath {
    param([string]$File)
    if (-not $File) { return $false }
    if ([System.IO.Path]::IsPathRooted($File)) { return $false }
    if ($File -match "(^|[\\/])\.\.([\\/]|$)") { return $false }
    if ($File -match ":") { return $false }
    return $true
}

function Convert-ToSlug {
    param([string]$Text)
    $slug = $Text.ToLowerInvariant()
    $slug = $slug -replace "[^a-z0-9]+", "-"
    $slug = $slug -replace "^-+", ""
    $slug = $slug -replace "-+$", ""
    if (-not $slug) { $slug = "memory-entry" }
    return $slug
}

function Invoke-Init {
    Initialize-MemoryRepo
    Write-Output "OK: Memory repo initialized at $script:MemDir"
}

function Invoke-Search {
    param(
        [string]$Keywords,
        [int]$Skip = 0,
        [string]$Mode = "auto"
    )
    Initialize-MemoryRepo

    if (-not $Keywords) {
        Write-Error "Usage: mem.ps1 search <keywords_csv> [skip] [mode] [--mode <and|or|auto>]"
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

    $normalizedMode = if ($Mode) { $Mode.Trim().ToLowerInvariant() } else { "auto" }
    if ($normalizedMode -notin @("and", "or", "auto")) {
        Write-Error "Error: mode must be one of: and, or, auto"
        return
    }

    $activeEntries = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $activeLines = @(& git -C $script:MemDir ls-tree -r --name-only HEAD -- entries/ 2>$null)
    foreach ($entry in $activeLines) {
        if ($entry -and $entry -ne "entries/.gitkeep") {
            [void]$activeEntries.Add($entry)
        }
    }

    function Get-SearchResults {
        param(
            [string[]]$SearchGrepArgs,
            [int]$SearchSkip,
            [string]$SearchMode
        )

        $limit = 20
        $batchSize = 200
        $rawSkip = 0
        $remainingSkip = [Math]::Max(0, $SearchSkip)
        $results = New-Object System.Collections.Generic.List[string]
        $modeArgs = @()
        if ($SearchMode -eq "and") { $modeArgs += "--all-match" }

        while ($results.Count -lt $limit) {
            $gitArgs = @("log") + $SearchGrepArgs + $modeArgs + @(
                "-i", "--skip=$rawSkip", "--max-count=$batchSize",
                "--format=%H%x09%s%x09%cd", "--date=iso",
                "--name-only", "--all", "--", "entries/"
            )

            $lines = @(& git -C $script:MemDir @gitArgs 2>$null)
            if ($lines.Count -eq 0) { break }

            $batchCommitCount = 0
            $currentHash = ""
            $currentSubject = ""
            $currentDate = ""
            $currentFile = ""

            foreach ($line in $lines) {
                if (-not $line) { continue }

                if ($line -match "^[0-9a-f]{40}`t") {
                    if ($currentHash) {
                        if (
                            $currentSubject -notlike "delete: remove *" -and
                            $currentFile -and
                            $activeEntries.Contains($currentFile)
                        ) {
                            if ($remainingSkip -gt 0) {
                                $remainingSkip--
                            }
                            else {
                                $results.Add("$currentHash|$currentSubject|$currentDate")
                                if ($results.Count -ge $limit) { break }
                            }
                        }
                    }

                    $parts = $line -split "`t", 3
                    if ($parts.Count -lt 3) {
                        $currentHash = ""
                        $currentSubject = ""
                        $currentDate = ""
                        $currentFile = ""
                        continue
                    }

                    $currentHash = $parts[0]
                    $currentSubject = $parts[1]
                    $currentDate = $parts[2]
                    $currentFile = ""
                    $batchCommitCount++
                    continue
                }

                if (-not $currentFile -and $line -like "entries/*.md") {
                    $currentFile = $line.Trim()
                }
            }

            if ($results.Count -lt $limit -and $currentHash) {
                if (
                    $currentSubject -notlike "delete: remove *" -and
                    $currentFile -and
                    $activeEntries.Contains($currentFile)
                ) {
                    if ($remainingSkip -gt 0) {
                        $remainingSkip--
                    }
                    else {
                        $results.Add("$currentHash|$currentSubject|$currentDate")
                    }
                }
            }

            if ($batchCommitCount -lt $batchSize) { break }
            $rawSkip += $batchSize
        }

        $results
    }

    if ($normalizedMode -eq "auto") {
        $autoMinResults = 3
        $andResults = @(Get-SearchResults -SearchGrepArgs $grepArgs -SearchSkip $Skip -SearchMode "and")
        if ($andResults.Count -ge $autoMinResults) {
            $andResults
        }
        else {
            Get-SearchResults -SearchGrepArgs $grepArgs -SearchSkip $Skip -SearchMode "or"
        }
        return
    }

    Get-SearchResults -SearchGrepArgs $grepArgs -SearchSkip $Skip -SearchMode $normalizedMode
}

function Get-EntryFileFromCommit {
    param([string]$CommitHash)

    if (-not $CommitHash) { return "" }

    $file = git -C $script:MemDir diff-tree --no-commit-id --name-only -r $CommitHash -- entries/ 2>$null | Select-Object -First 1
    if (-not $file) {
        $file = git -C $script:MemDir diff-tree --root --no-commit-id --name-only -r $CommitHash -- entries/ 2>$null | Select-Object -First 1
    }

    return $file
}

function Invoke-Read {
    param([string]$CommitHash)
    Initialize-MemoryRepo

    if (-not $CommitHash) {
        Write-Error "Usage: mem.ps1 read <commit_hash>"
        return
    }

    $file = Get-EntryFileFromCommit -CommitHash $CommitHash

    if ($file) {
        git -C $script:MemDir show "${CommitHash}:${file}" 2>$null
    }
    else {
        Write-Error "Error: no entry file found in commit $CommitHash"
    }
}

function Invoke-Write {
    param([string[]]$Params)
    Initialize-MemoryRepo

    $file = ""
    $title = ""
    $body = ""
    $content = ""
    $contentFile = ""
    $bodyFile = ""
    $directContentFile = ""
    $reuseExistingFile = $false
    $deleteSourceFile = $false

    for ($i = 0; $i -lt $Params.Count; $i++) {
        switch ($Params[$i]) {
            "--file" {
                if ($i + 1 -ge $Params.Count) { Write-Error "Error: --file requires a value"; return }
                $file = $Params[++$i]
            }
            "--title" {
                if ($i + 1 -ge $Params.Count) { Write-Error "Error: --title requires a value"; return }
                $title = $Params[++$i]
            }
            "--body" {
                if ($i + 1 -ge $Params.Count) { Write-Error "Error: --body requires a value"; return }
                $body = $Params[++$i]
            }
            "--body-file" {
                if ($i + 1 -ge $Params.Count) { Write-Error "Error: --body-file requires a value"; return }
                $bodyFile = $Params[++$i]
            }
            "--content" {
                if ($i + 1 -ge $Params.Count) { Write-Error "Error: --content requires a value"; return }
                $content = $Params[++$i]
            }
            "--content-file" {
                if ($i + 1 -ge $Params.Count) { Write-Error "Error: --content-file requires a value"; return }
                $contentFile = $Params[++$i]
            }
            default {
                Write-Error "Unknown option: $($Params[$i])"
                return
            }
        }
    }

    if (-not $title) {
        Write-Error "Usage: mem.ps1 write --title <title> [--file <path>] [--body <body> | --body-file <path>] [--content-file <path> | --content <markdown>]"
        return
    }

    if ($body -and $bodyFile) {
        Write-Error "Error: use only one of --body or --body-file"
        return
    }

    if ($bodyFile -and -not (Test-Path -LiteralPath $bodyFile -PathType Leaf)) {
        Write-Error "Error: body file not found: $bodyFile"
        return
    }

    if ($bodyFile) {
        $body = [System.IO.File]::ReadAllText($bodyFile, [System.Text.UTF8Encoding]::new($false))
    }

    if ($content -and $contentFile) {
        Write-Error "Error: use only one of --content or --content-file"
        return
    }

    if ($content -and -not $contentFile) {
        Write-Warning "Passing markdown via --content may hit shell escaping issues. Prefer writing markdown to a temp .md file and pass --content-file."
    }

    if ($contentFile -and -not (Test-Path -LiteralPath $contentFile)) {
        Write-Error "Error: content file not found: $contentFile"
        return
    }

    if ($contentFile) {
        $directContentFile = Get-DirectEntryPath -Path $contentFile
    }

    if ($file) {
        $file = Resolve-EntryPath -File $file
        if ($directContentFile -and $file -ne $directContentFile) {
            Write-Error "Error: --file must match the existing .mem/entries path referenced by --content-file"
            return
        }
    }
    elseif ($directContentFile) {
        $file = $directContentFile
    }
    elseif ($content -or $contentFile) {
        $timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
        $slug = Convert-ToSlug -Text $title
        $file = "entries/$timestamp-$slug.md"
    }
    else {
        Write-Error "Error: missing content. Use --content, --content-file, or pre-write a .mem/entries file and pass --file."
        return
    }

    if (-not (Test-SafeEntryPath -File $file)) {
        Write-Error "Error: invalid file path: $file"
        return
    }

    if (-not $file.EndsWith(".md", [StringComparison]::OrdinalIgnoreCase)) {
        $file = "$file.md"
    }

    Sync-Branch | Out-Null

    $fullPath = Join-Path $script:MemDir $file
    $targetDir = Split-Path -Parent $fullPath

    if ($directContentFile) {
        $reuseExistingFile = $true
    }
    elseif (-not $content -and -not $contentFile) {
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $reuseExistingFile = $true
        }
        else {
            Write-Error "Error: existing entry file not found: $fullPath"
            return
        }
    }
    elseif ($contentFile) {
        $deleteSourceFile = $true
    }

    if ($reuseExistingFile) {
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            Write-Error "Error: existing entry file not found after branch sync: $fullPath"
            return
        }
    }
    else {
        if ($targetDir) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        if ($contentFile) {
            # Always store entry files as UTF-8 (no BOM). If the source isn't valid UTF-8
            # (e.g. a caller on Windows wrote the temp md as system ANSI/GBK), transcode
            # from the default ANSI code page into UTF-8 before committing.
            $srcBytes = [System.IO.File]::ReadAllBytes($contentFile)
            $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
            $isValidUtf8 = $true
            try { $null = $strictUtf8.GetString($srcBytes) }
            catch { $isValidUtf8 = $false }

            if (-not $isValidUtf8) {
                $decoded = [System.Text.Encoding]::Default.GetString($srcBytes)
                [System.IO.File]::WriteAllText($fullPath, $decoded, $script:Utf8NoBom)
            }
            elseif ($srcBytes.Length -ge 3 -and $srcBytes[0] -eq 0xEF -and $srcBytes[1] -eq 0xBB -and $srcBytes[2] -eq 0xBF) {
                $stripped = New-Object byte[] ($srcBytes.Length - 3)
                [System.Buffer]::BlockCopy($srcBytes, 3, $stripped, 0, $stripped.Length)
                [System.IO.File]::WriteAllBytes($fullPath, $stripped)
            }
            else {
                [System.IO.File]::WriteAllBytes($fullPath, $srcBytes)
            }
        }
        else {
            [System.IO.File]::WriteAllText($fullPath, $content + "`n", $script:Utf8NoBom)
        }
    }

    git -C $script:MemDir add -- $file
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Error: git add failed for $file"
        return
    }

    # Pass commit message via a UTF-8 (no BOM) file rather than -m to bypass Windows
    # argv ANSI conversion, which would otherwise mangle non-ASCII (e.g. Chinese) chars.
    $msgFile = Join-Path $env:TEMP ("gitmemo-commit-" + [guid]::NewGuid().ToString() + ".msg")
    try {
        $msg = if ($body) { "$title`n`n$body" } else { "$title" }
        [System.IO.File]::WriteAllText($msgFile, $msg, $script:Utf8NoBom)
        git -C $script:MemDir commit -q -F $msgFile
        $commitExit = $LASTEXITCODE
    }
    finally {
        Remove-Item -LiteralPath $msgFile -Force -ErrorAction SilentlyContinue
    }
    if ($commitExit -ne 0) {
        git -C $script:MemDir reset -q HEAD -- $file 2>$null | Out-Null
        if (-not $reuseExistingFile -and (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            Remove-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
        }
        Write-Error "Error: git commit failed for $file (rolled back)"
        return
    }

    $hash = (git -C $script:MemDir rev-parse HEAD).Trim()

    if ($deleteSourceFile) {
        try {
            Remove-Item -LiteralPath $contentFile -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Write succeeded but failed to delete content file: $contentFile. $($_.Exception.Message)"
        }
    }

    Write-Output "OK: $hash|$file"
}

function Invoke-Delete {
    param([string]$CommitHash)
    Initialize-MemoryRepo

    if (-not $CommitHash) {
        Write-Error "Usage: mem.ps1 delete <commit_hash>"
        return
    }

    $file = Get-EntryFileFromCommit -CommitHash $CommitHash

    if (-not $file) {
        Write-Error "Error: no entry file found in commit $CommitHash"
        return
    }

    $fullPath = Join-Path $script:MemDir $file
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        git -C $script:MemDir rm -q -- $file
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Error: git rm failed for $file"
            return
        }
        $basename = [System.IO.Path]::GetFileNameWithoutExtension($file)
        $msgFile = Join-Path $env:TEMP ("gitmemo-commit-" + [guid]::NewGuid().ToString() + ".msg")
        try {
            [System.IO.File]::WriteAllText($msgFile, "delete: remove $basename", $script:Utf8NoBom)
            git -C $script:MemDir commit -q -F $msgFile
            $commitExit = $LASTEXITCODE
        }
        finally {
            Remove-Item -LiteralPath $msgFile -Force -ErrorAction SilentlyContinue
        }
        if ($commitExit -ne 0) {
            git -C $script:MemDir reset -q HEAD -- $file 2>$null | Out-Null
            Write-Error "Error: git commit failed while deleting $file (rolled back staging)"
            return
        }
        Write-Output "OK: deleted $file"
    }
    else {
        Write-Error "Error: file already deleted: $file"
    }
}

switch ($Command) {
    "init" { Invoke-Init }
    "search" {
        $kw = if ($RemainingParameters.Count -ge 1) { $RemainingParameters[0] } else { "" }
        $sk = 0
        $mode = "auto"
        $idx = 1

        if ($RemainingParameters.Count -ge 2 -and $RemainingParameters[1] -match "^-?\d+$") {
            $sk = [int]$RemainingParameters[1]
            $idx = 2
        }

        if ($RemainingParameters.Count -gt $idx -and $RemainingParameters[$idx] -ne "--mode") {
            $mode = $RemainingParameters[$idx]
            $idx++
        }

        while ($idx -lt $RemainingParameters.Count) {
            switch ($RemainingParameters[$idx]) {
                "--mode" {
                    if ($idx + 1 -ge $RemainingParameters.Count) {
                        Write-Error "Error: --mode requires a value (and|or|auto)"
                        return
                    }
                    $mode = $RemainingParameters[$idx + 1]
                    $idx += 2
                }
                default {
                    Write-Error "Unknown option for search: $($RemainingParameters[$idx])"
                    return
                }
            }
        }

        Invoke-Search -Keywords $kw -Skip $sk -Mode $mode
    }
    "read" { Invoke-Read -CommitHash ($RemainingParameters | Select-Object -First 1) }
    "write" { Invoke-Write -Params $RemainingParameters }
    "delete" { Invoke-Delete -CommitHash ($RemainingParameters | Select-Object -First 1) }
    default {
        Write-Host "Usage: mem.ps1 {init|search|read|write|delete}"
        Write-Host "  init                                    Initialize .mem repo"
        Write-Host "  search <keywords_csv> [skip] [mode] [--mode M]  Search memories (M: and|or|auto)"
        Write-Host "  read <commit_hash>                      Read memory content"
        Write-Host "  write --title T [--file F] [--body B | --body-file P] [--content-file P | --content C]"
        Write-Host "  delete <commit_hash>                    Delete memory entry"
    }
}
