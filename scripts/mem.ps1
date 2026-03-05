#Requires -Version 5.1

# Parse positional CLI arguments manually to avoid binding side effects with automatic variables.
$Command = if ($args.Count -gt 0) { [string]$args[0] } else { "" }
$RemainingParameters = if ($args.Count -gt 1) { @($args[1..($args.Count - 1)]) } else { @() }

$ErrorActionPreference = "Stop"

function Find-RepoRoot {
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
    if ($root) { return $root }
    return (Get-Location).Path
}

function Resolve-MemDir {
    $root = Find-RepoRoot
    return Join-Path $root ".mem"
}

$script:QmdCollectionName = "gitmemo"
$script:QmdIndexName = $null
$script:QmdCommand = $null
$script:QmdModelsBootstrapDone = $false

function Get-QmdCommand {
    if ($script:QmdCommand) { return $script:QmdCommand }

    $cmd = Get-Command qmd.cmd -ErrorAction SilentlyContinue
    if ($cmd) {
        $script:QmdCommand = $cmd.Source
        return $script:QmdCommand
    }

    $fallback = Get-Command qmd -ErrorAction SilentlyContinue
    if ($fallback) {
        $script:QmdCommand = $fallback.Source
        return $script:QmdCommand
    }

    return $null
}

function Test-QmdAvailable {
    return [bool](Get-QmdCommand)
}

function Get-QmdRootDir {
    return Join-Path $script:MemDir ".qmd"
}

function Get-QmdConfigDir {
    return Join-Path (Get-QmdRootDir) "config"
}

function Get-QmdCacheDir {
    return Join-Path (Get-QmdRootDir) "cache"
}

function Get-QmdIndexName {
    if ($script:QmdIndexName) { return $script:QmdIndexName }
    $script:QmdIndexName = "gitmemo"
    return $script:QmdIndexName
}

function Get-QmdDbPath {
    param([string]$IndexName)
    return Join-Path (Get-QmdCacheDir) "$IndexName.sqlite"
}

function Get-QmdModelBootstrapMarkerPath {
    return Join-Path (Get-QmdRootDir) "models.bootstrap.ok"
}

function Initialize-QmdRuntime {
    param([string]$IndexName)

    New-Item -ItemType Directory -Path (Get-QmdConfigDir) -Force | Out-Null
    New-Item -ItemType Directory -Path (Get-QmdCacheDir) -Force | Out-Null

    $env:QMD_CONFIG_DIR = Get-QmdConfigDir
    $env:XDG_CACHE_HOME = Get-QmdCacheDir
    $env:INDEX_PATH = Get-QmdDbPath -IndexName $IndexName
}

function Invoke-QmdIndexed {
    param(
        [string]$IndexName,
        [string[]]$Arguments,
        [switch]$CaptureOutput
    )

    Initialize-QmdRuntime -IndexName $IndexName
    $qmdCommand = Get-QmdCommand
    if (-not $qmdCommand) {
        if ($CaptureOutput) {
            return [pscustomobject]@{
                ExitCode = 1
                Output = @()
            }
        }
        return 1
    }

    if ($CaptureOutput) {
        try {
            $output = @(& $qmdCommand --index $IndexName @Arguments 2>$null)
            $exitCode = $LASTEXITCODE
        }
        catch {
            $output = @()
            $exitCode = 1
        }

        return [pscustomobject]@{
            ExitCode = $exitCode
            Output = $output
        }
    }

    try {
        & $qmdCommand --index $IndexName @Arguments 1>$null 2>$null
        return $LASTEXITCODE
    }
    catch {
        return 1
    }
}

function Ensure-QmdModels {
    if ($script:QmdModelsBootstrapDone) { return $true }

    $markerPath = Get-QmdModelBootstrapMarkerPath
    if (Test-Path -LiteralPath $markerPath) {
        $script:QmdModelsBootstrapDone = $true
        return $true
    }

    $indexName = Get-QmdIndexName
    $pullExitCode = Invoke-QmdIndexed -IndexName $indexName -Arguments @("pull")
    if ($pullExitCode -ne 0) { return $false }

    $markerDir = Split-Path -Parent $markerPath
    if ($markerDir) {
        New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
    }
    New-Item -ItemType File -Path $markerPath -Force | Out-Null
    $script:QmdModelsBootstrapDone = $true
    return $true
}

function Ensure-QmdCollection {
    if (-not (Test-QmdAvailable)) { return $false }
    if (-not (Ensure-QmdModels)) { return $false }

    $indexName = Get-QmdIndexName
    if ((Invoke-QmdIndexed -IndexName $indexName -Arguments @("collection", "show", $script:QmdCollectionName)) -eq 0) { return $true }

    $addExitCode = Invoke-QmdIndexed -IndexName $indexName -Arguments @("collection", "add", $script:MemDir, "--name", $script:QmdCollectionName, "--mask", "**/*.md")
    if ($addExitCode -ne 0) { return $false }

    $embedExitCode = Invoke-QmdIndexed -IndexName $indexName -Arguments @("embed")
    return ($embedExitCode -eq 0)
}

function Sync-QmdIndexBestEffort {
    if (-not (Test-QmdAvailable)) { return }
    if (-not (Ensure-QmdCollection)) {
        Write-Warning "qmd detected but failed to initialize index; keeping git backend available."
        return
    }

    $indexName = Get-QmdIndexName
    $updateExitCode = Invoke-QmdIndexed -IndexName $indexName -Arguments @("update")
    if ($updateExitCode -ne 0) {
        Write-Warning "qmd update failed; qmd index may be stale."
        return
    }

    $embedExitCode = Invoke-QmdIndexed -IndexName $indexName -Arguments @("embed")
    if ($embedExitCode -ne 0) {
        Write-Warning "qmd embed failed; qmd vector index may be stale."
    }
}

function Initialize-MemoryRepo {
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
    if ($File -like "entries/*") { return $File }
    return "entries/$File"
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

    $keywordTerms = New-Object System.Collections.Generic.List[string]
    $grepArgs = @()
    foreach ($kw in ($Keywords -split ',')) {
        $kw = $kw.Trim()
        if ($kw) {
            [void]$keywordTerms.Add($kw)
            $grepArgs += "--grep=$kw"
        }
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

    function Get-QmdSearchResultsForMode {
        param(
            [string[]]$SearchTerms,
            [int]$SearchSkip,
            [string]$SearchMode
        )

        if (-not (Test-QmdAvailable)) {
            return [pscustomobject]@{ Handled = $false; Success = $false; Results = @() }
        }

        if (-not (Ensure-QmdCollection)) {
            return [pscustomobject]@{ Handled = $true; Success = $false; Results = @() }
        }

        $queryText = if ($SearchMode -eq "or") {
            [string]::Join(" OR ", $SearchTerms)
        }
        else {
            [string]::Join(" ", $SearchTerms)
        }

        if (-not $queryText) {
            return [pscustomobject]@{ Handled = $true; Success = $true; Results = @() }
        }

        $indexName = Get-QmdIndexName
        $qmdResult = Invoke-QmdIndexed -IndexName $indexName -Arguments @("query", $queryText, "--all", "--files", "--min-score", "0", "-c", $script:QmdCollectionName) -CaptureOutput
        if ($qmdResult.ExitCode -ne 0) {
            return [pscustomobject]@{ Handled = $true; Success = $false; Results = @() }
        }
        $rawLines = @($qmdResult.Output)

        $limit = 20
        $remainingSkip = [Math]::Max(0, $SearchSkip)
        $results = New-Object System.Collections.Generic.List[string]
        $seenHashes = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $prefix = "qmd://$script:QmdCollectionName/"

        $activeEntries = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $activeLines = @(& git -C $script:MemDir ls-tree -r --name-only HEAD -- entries/ 2>$null)
        foreach ($entry in $activeLines) {
            if ($entry -and $entry -ne "entries/.gitkeep") {
                [void]$activeEntries.Add($entry)
            }
        }

        foreach ($line in $rawLines) {
            if (-not $line) { continue }
            if ($line -notmatch "^[^,]*,[^,]*,([^,]+)") { continue }

            $qmdPath = $Matches[1].Trim()
            if (-not $qmdPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { continue }

            $relativePath = $qmdPath.Substring($prefix.Length)
            if ($relativePath -notlike "entries/*.md") { continue }
            if (-not $activeEntries.Contains($relativePath)) { continue }

            $metaOutput = @(& git -C $script:MemDir log -n 1 --format="%H|%s|%cd" --date=iso -- $relativePath 2>$null)
            if ($metaOutput.Count -eq 0) { continue }

            $metaLine = ($metaOutput | Select-Object -First 1).Trim()
            if (-not $metaLine) { continue }

            $hash = ($metaLine -split "\|", 2)[0]
            if (-not $hash) { continue }
            if ($seenHashes.Contains($hash)) { continue }
            [void]$seenHashes.Add($hash)

            if ($remainingSkip -gt 0) {
                $remainingSkip--
                continue
            }

            $results.Add($metaLine)
            if ($results.Count -ge $limit) { break }
        }

        return [pscustomobject]@{ Handled = $true; Success = $true; Results = @($results) }
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

        # Build an in-memory set of active entry files once to avoid per-commit git calls.
        $activeEntries = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $activeLines = @(& git -C $script:MemDir ls-tree -r --name-only HEAD -- entries/ 2>$null)
        foreach ($entry in $activeLines) {
            if ($entry -and $entry -ne "entries/.gitkeep") {
                [void]$activeEntries.Add($entry)
            }
        }

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

    $termArray = $keywordTerms.ToArray()
    if (Test-QmdAvailable) {
        if ($normalizedMode -eq "auto") {
            $autoMinResults = 3
            $andAttempt = Get-QmdSearchResultsForMode -SearchTerms $termArray -SearchSkip $Skip -SearchMode "and"
            if ($andAttempt.Handled) {
                if ($andAttempt.Success) {
                    if ($andAttempt.Results.Count -ge $autoMinResults) {
                        $andAttempt.Results
                        return
                    }

                    $orAttempt = Get-QmdSearchResultsForMode -SearchTerms $termArray -SearchSkip $Skip -SearchMode "or"
                    if ($orAttempt.Success) {
                        $orAttempt.Results
                        return
                    }

                    Write-Warning "qmd search failed in auto fallback; using git log backend."
                }
                else {
                    Write-Warning "qmd search failed in auto mode; using git log backend."
                }
            }
        }
        else {
            $qmdAttempt = Get-QmdSearchResultsForMode -SearchTerms $termArray -SearchSkip $Skip -SearchMode $normalizedMode
            if ($qmdAttempt.Handled) {
                if ($qmdAttempt.Success) {
                    $qmdAttempt.Results
                    return
                }

                Write-Warning "qmd search failed; using git log backend."
            }
        }
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

function Invoke-Read {
    param([string]$CommitHash)
    Initialize-MemoryRepo

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
        Write-Error "Usage: mem.ps1 write --title <title> [--file <path>] (--content-file <path> | --content <markdown>) [--body <body>]"
        return
    }

    if ($content -and $contentFile) {
        Write-Error "Error: use only one of --content or --content-file"
        return
    }

    if (-not $content -and -not $contentFile) {
        Write-Error "Error: missing content. Use --content or --content-file."
        return
    }

    if ($content -and -not $contentFile) {
        Write-Warning "Passing markdown via --content may hit shell escaping issues. Prefer writing markdown to a temp .md file and pass --content-file."
    }

    if ($contentFile -and -not (Test-Path -LiteralPath $contentFile)) {
        Write-Error "Error: content file not found: $contentFile"
        return
    }

    if (-not $file) {
        $timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
        $slug = Convert-ToSlug -Text $title
        $file = "entries/$timestamp-$slug.md"
    }
    else {
        $file = Resolve-EntryPath -File $file
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
    if ($targetDir) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    if ($contentFile) {
        Copy-Item -LiteralPath $contentFile -Destination $fullPath -Force
    }
    else {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($fullPath, $content + "`n", $utf8NoBom)
    }

    git -C $script:MemDir add $file
    if ($body) {
        git -C $script:MemDir commit -q -m $title -m $body
    }
    else {
        git -C $script:MemDir commit -q -m $title
    }

    $hash = git -C $script:MemDir rev-parse HEAD

    if ($contentFile) {
        try {
            Remove-Item -LiteralPath $contentFile -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Write succeeded but failed to delete content file: $contentFile. $($_.Exception.Message)"
        }
    }

    Sync-QmdIndexBestEffort

    Write-Output "OK: $hash|$file"
}

function Invoke-Delete {
    param([string]$CommitHash)
    Initialize-MemoryRepo

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
        Sync-QmdIndexBestEffort
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
        Write-Host "  write --title T [--file F] (--content-file P | --content C) [--body B]"
        Write-Host "  delete <commit_hash>                    Delete memory entry"
    }
}
