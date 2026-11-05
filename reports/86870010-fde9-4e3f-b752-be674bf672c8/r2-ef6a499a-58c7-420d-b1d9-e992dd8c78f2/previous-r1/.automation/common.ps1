Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-TuUtf8([string]$Path, [string]$Text) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Write-TuJson([string]$Path, $Value) {
    $tmp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    Write-TuUtf8 $tmp ($Value | ConvertTo-Json -Depth 40)
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($tmp, $Path, [System.Management.Automation.Language.NullString]::Value) }
    else { [IO.File]::Move($tmp, $Path) }
}

function Read-TuJson([string]$Path) {
    return ([IO.File]::ReadAllText($Path) | ConvertFrom-Json)
}

function Quote-TuArgument([string]$Value) {
    # Windows CommandLineToArgvW quoting; no shell interpolation.
    '"' + ([regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
}

function Resolve-TuApplication([string]$Name) {
    # Git Bash may put cmd/git.exe AND mingw64/bin/git.exe on PATH.
    $command = Get-Command $Name -CommandType Application -ErrorAction Stop | Select-Object -First 1
    return $command.Source
}

function Invoke-TuProcess {
    param([string]$Executable, [string[]]$Arguments = @(), [string]$InputText = '',
          [string]$WorkingDirectory, [int]$TimeoutSeconds = 60, [hashtable]$Environment = @{})
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = (($Arguments | ForEach-Object { Quote-TuArgument $_ }) -join ' ')
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    foreach ($key in $Environment.Keys) {
        if ($null -eq $Environment[$key]) { $info.EnvironmentVariables.Remove($key) }
        else { $info.EnvironmentVariables[$key] = [string]$Environment[$key] }
    }
    $process = New-Object Diagnostics.Process
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $inputWriter = New-Object IO.StreamWriter($process.StandardInput.BaseStream, (New-Object Text.UTF8Encoding($false)))
        $inputTask = $inputWriter.WriteAsync($InputText)
        if (-not $inputTask.Wait($TimeoutSeconds * 1000)) { throw 'PROCESS_TIMEOUT' }
        $inputWriter.Close()
        $remaining = [Math]::Max(1, $TimeoutSeconds * 1000 - [int]$watch.ElapsedMilliseconds)
        if (-not $process.WaitForExit($remaining)) { throw 'PROCESS_TIMEOUT' }
        $process.WaitForExit()
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdout.Result; Stderr = $stderr.Result }
    } catch {
        if ($process.Id -and -not $process.HasExited) {
            $killer = Join-Path $env:SystemRoot 'System32\taskkill.exe'
            & $killer /PID $process.Id /T /F 2>&1 | Out-Null
        }
        throw 'PROCESS_TIMEOUT_OR_START_FAILURE'
    } finally { $process.Dispose() }
}

function Invoke-TuGit([string]$Root, [string[]]$Arguments) {
    $r = Invoke-TuProcess (Resolve-TuApplication 'git') (@('-c','core.quotepath=false') + $Arguments) '' $Root
    if ($r.ExitCode -ne 0) { throw 'GIT_COMMAND_FAILED' }
    return $r.Stdout.TrimEnd("`r", "`n")
}

function Assert-TuSafePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z0-9_@(). /+-]+$' -or
        $Path.StartsWith('/') -or $Path.EndsWith('/') -or $Path.Contains('//')) { throw 'UNSAFE_PATH' }
    foreach ($segment in $Path.Split('/')) {
        if ($segment -in @('.','..') -or $segment -match '[. ]$' -or
            $segment -match '^(?i:con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\.|$)') { throw 'UNSAFE_PATH' }
    }
}

function Test-TuReportPath([string]$Path) {
    return $Path -ceq 'agentReport.md' -or $Path.StartsWith('reports/', [StringComparison]::Ordinal) -or
        $Path.StartsWith('.agents/state/', [StringComparison]::Ordinal)
}

function Test-TuSecretPath([string]$Path) {
    return $Path -match '(?i)(^|/)(\.env(?:\..*)?|auth\.json|oauth_creds\.json|credentials[^/]*|[^/]+\.(pem|key|p12|pfx))$' -or
        $Path -match '(?i)^(supabase/\.temp/|\.git/|\.gemini/|\.codex/)'
}

function Assert-TuNoSecrets([string]$Text) {
    if ($Text -match '(sbp_[a-zA-Z0-9]{20,}|sk-[a-zA-Z0-9_-]{24,}|AIza[a-zA-Z0-9_-]{30,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|postgres(?:ql)?://[^\s:/]+:[^\s@]+@)') {
        throw 'SECRET_PATTERN_DETECTED'
    }
}

function Get-TuConfig([string]$Root) {
    $c = Read-TuJson (Join-Path $Root '.automation/config.json')
    $required = @('schema_version','reviewer_model','reviewer_cli_version','max_fix_attempts','allowed_branch','review_trigger',
        'auto_fix','auto_merge','auto_push_main','auto_push','report_path','report_history_path','review_timeout_seconds','fix_timeout_seconds',
        'test_timeout_seconds','network_retries','max_snapshot_bytes','max_file_bytes','minimum_fix_confidence','allowed_edit_roots','test_commands')
    $names = @($c.PSObject.Properties.Name)
    if (@($required | Where-Object { $_ -notin $names }).Count -or @($names | Where-Object { $_ -notin $required }).Count) { throw 'INVALID_CONFIG_KEYS' }
    foreach ($name in @('auto_fix','auto_merge','auto_push_main','auto_push')) {
        if ($c.$name -isnot [bool]) { throw 'INVALID_CONFIG_BOOLEAN' }
    }
    if ($c.schema_version -isnot [int] -or $c.schema_version -ne 1 -or $c.reviewer_model -cne 'gemini-4-argon' -or
        $c.allowed_branch -cne 'tu' -or $c.review_trigger -cne 'post-commit' -or
        $c.auto_merge -or $c.auto_push_main -or $c.auto_push -or
        $c.report_path -cne 'agentReport.md' -or $c.report_history_path -cne 'reports/') { throw 'UNSAFE_CONFIG' }
    foreach ($name in @('max_fix_attempts','review_timeout_seconds','fix_timeout_seconds','test_timeout_seconds','network_retries','max_snapshot_bytes','max_file_bytes')) {
        if ($c.$name -isnot [int] -and $c.$name -isnot [long]) { throw 'INVALID_CONFIG_INTEGER' }
    }
    if ($c.max_fix_attempts -lt 0 -or $c.max_fix_attempts -gt 3 -or $c.network_retries -lt 0 -or $c.network_retries -gt 2 -or
        $c.minimum_fix_confidence -lt 0.5 -or $c.minimum_fix_confidence -gt 1 -or
        $c.max_snapshot_bytes -lt 1000 -or $c.max_snapshot_bytes -gt 10000000 -or
        $c.max_file_bytes -lt 100 -or $c.max_file_bytes -gt $c.max_snapshot_bytes -or
        $c.reviewer_cli_version -notmatch '^\d+\.\d+\.\d+$') { throw 'INVALID_CONFIG_RANGE' }
    foreach ($name in @('review_timeout_seconds','fix_timeout_seconds','test_timeout_seconds')) {
        if ($c.$name -lt 1 -or $c.$name -gt 1800) { throw 'INVALID_TIMEOUT' }
    }
    if ($c.allowed_edit_roots -isnot [array] -or $c.allowed_edit_roots.Count -eq 0 -or $c.test_commands -isnot [array]) { throw 'INVALID_CONFIG_ARRAY' }
    foreach ($prefix in $c.allowed_edit_roots) {
        Assert-TuSafePath $prefix.TrimEnd('/')
        if ($prefix -notin @('frontend/','backend/','supabase/migrations/','tests/')) { throw 'UNSAFE_EDIT_ROOT' }
    }
    foreach ($command in $c.test_commands) {
        if ($command.executable -isnot [string] -or [string]::IsNullOrWhiteSpace($command.executable) -or $command.arguments -isnot [array]) { throw 'INVALID_TEST_COMMAND' }
        foreach ($a in $command.arguments) { if ($a -isnot [string]) { throw 'INVALID_TEST_ARGUMENT' } }
    }
    return $c
}

function Get-TuFingerprint([string]$Root) {
    $paths = @('AGENTS.md','GEMINI_REVIEW.md','.gitignore')
    foreach ($folder in @('.automation','.githooks','.agents/agents','.agents/skills')) {
        if (Test-Path -LiteralPath (Join-Path $Root $folder)) {
            $paths += @(Get-ChildItem -LiteralPath (Join-Path $Root $folder) -File -Recurse | ForEach-Object { $_.FullName.Substring($Root.Length + 1).Replace('\','/') })
        }
    }
    $items = foreach ($path in ($paths | Sort-Object -Unique)) {
        if ($path -eq '.automation/config.json') {
            $config = Get-TuConfig $Root
            $path + ':' + ($config | ConvertTo-Json -Depth 20 -Compress)
        } else { $path + ':' + (Get-FileHash -LiteralPath (Join-Path $Root $path) -Algorithm SHA256).Hash }
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($items -join "`n"))))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-TuActivation([string]$Root) {
    $fingerprint = Get-TuFingerprint $Root
    foreach ($name in @('fixture-tests','live-probes')) {
        $p = Join-Path $Root ".agents/state/$name.json"
        if (-not (Test-Path -LiteralPath $p)) { throw 'ACTIVATION_RECEIPTS_MISSING' }
        $receipt = Read-TuJson $p
        if ($receipt.status -ne 'PASSED' -or $receipt.fingerprint -ne $fingerprint) { throw 'ACTIVATION_RECEIPTS_STALE_OR_FAILED' }
        if ($name -eq 'fixture-tests' -and ($receipt.provenance -cne 'FIXTURE_TESTS_ONLY' -or $receipt.failed -ne 0 -or $receipt.passed -lt 1)) { throw 'ACTIVATION_TEST_RECEIPT_INVALID' }
        if ($name -eq 'live-probes' -and ($receipt.provenance -cne 'LIVE_CLI_PROBES' -or -not $receipt.codex_login -or -not $receipt.codex_exec -or
            -not $receipt.gemini_headless -or $receipt.gemini_actual_model -cne 'gemini-4-argon' -or $receipt.gemini_tool_calls -ne 0)) { throw 'ACTIVATION_LIVE_RECEIPT_INVALID' }
    }
}

function Assert-TuCliAllowed([string]$Root) {
    if (Test-Path -LiteralPath (Join-Path $Root '.automation/DESKTOP_ONLY')) {
        throw 'CLI_DISABLED_DESKTOP_ONLY'
    }
}

function Test-TuEnabled([string]$Root) {
    if (Test-Path -LiteralPath (Join-Path $Root '.automation/DESKTOP_ONLY')) { return $false }
    $path = Join-Path $Root '.agents/state/activation.json'
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $activation = Read-TuJson $path
    return $activation.enabled -eq $true -and $activation.product_owner_approved -eq $true -and
        $activation.fingerprint -eq (Get-TuFingerprint $Root)
}

function Assert-TuClean([string]$Root) {
    $status = Invoke-TuGit $Root @('status','--porcelain=v1','-z','--untracked-files=all')
    foreach ($entry in ($status -split "`0" | Where-Object { $_ })) {
        if ($entry.Length -lt 4 -or -not (Test-TuReportPath $entry.Substring(3))) { throw 'WORKTREE_NOT_CLEAN' }
    }
}

function Get-TuChanges([string]$Root, [string]$Base, [string]$Commit) {
    return @( (Invoke-TuGit $Root @('diff','--no-renames','--name-only','-z',$Base,$Commit,'--')) -split "`0" | Where-Object { $_ })
}

function New-TuSnapshot([string]$Root, $Config, [string]$Base, [string]$Commit, $Parent) {
    $changed = @(Get-TuChanges $Root $Base $Commit)
    if (@($changed | Where-Object { Test-TuSecretPath $_ }).Count) { throw 'SECRET_FILE_CHANGED' }
    $files = New-Object Collections.Generic.List[object]
    $total = 0
    $entries = (Invoke-TuGit $Root @('ls-tree','-r','-z',$Commit)) -split "`0"
    foreach ($entry in $entries) {
        if (-not $entry) { continue }
        $parts = $entry -split "`t", 2
        $path = $parts[1]
        if ((Test-TuReportPath $path) -or (Test-TuSecretPath $path)) { continue }
        Assert-TuSafePath $path
        if ($parts[0] -notmatch '^100(644|755) blob ') { throw 'UNSUPPORTED_GIT_ENTRY' }
        $content = Invoke-TuGit $Root @('show',($Commit + ':' + $path))
        $size = [Text.Encoding]::UTF8.GetByteCount($content)
        if ($content.Contains([string][char]0) -or $size -gt $Config.max_file_bytes) {
            if ($path -in $changed) { throw 'CHANGED_FILE_NOT_REVIEWABLE' }
            throw 'SNAPSHOT_FILE_NOT_REVIEWABLE'
        }
        Assert-TuNoSecrets $content
        $total += $size
        if ($total -gt $Config.max_snapshot_bytes) { throw 'SNAPSHOT_TOO_LARGE' }
        $files.Add([pscustomobject]@{ path=$path; content=$content; source='target'; line_count=([regex]::Matches($content,"`n").Count+1) })
    }
    foreach ($path in $changed) {
        if ((Test-TuReportPath $path) -or @($files | Where-Object path -CEQ $path).Count) { continue }
        Assert-TuSafePath $path
        $content = Invoke-TuGit $Root @('show',($Base + ':' + $path))
        if ($content.Contains([string][char]0) -or [Text.Encoding]::UTF8.GetByteCount($content) -gt $Config.max_file_bytes) { throw 'DELETED_FILE_NOT_REVIEWABLE' }
        Assert-TuNoSecrets $content
        $total += [Text.Encoding]::UTF8.GetByteCount($content)
        if ($total -gt $Config.max_snapshot_bytes) { throw 'SNAPSHOT_TOO_LARGE' }
        $files.Add([pscustomobject]@{ path=$path; content=$content; source='base_deleted'; line_count=([regex]::Matches($content,"`n").Count+1) })
    }
    $diff = Invoke-TuGit $Root @('diff','--no-ext-diff','--no-textconv','--no-renames',$Base,$Commit,'--', '.', ':!agentReport.md', ':!reports', ':!.agents/state')
    Assert-TuNoSecrets $diff
    if ($total + [Text.Encoding]::UTF8.GetByteCount($diff) -gt $Config.max_snapshot_bytes) { throw 'SNAPSHOT_TOO_LARGE' }
    return [pscustomobject]@{ commit_sha=$Commit; parent_sha=$Parent; base_sha=$Base; changed_files=$changed; diff=$diff; files=@($files.ToArray()) }
}

function Assert-TuFields($Object, [string[]]$Fields) {
    if ($null -eq $Object -or $Object -isnot [pscustomobject]) { throw 'INVALID_JSON_OBJECT' }
    $names = @($Object.PSObject.Properties.Name)
    if (@($names | Where-Object { $_ -notin $Fields }).Count -or @($Fields | Where-Object { $_ -notin $names }).Count) { throw 'INVALID_JSON_FIELDS' }
}

function Assert-TuString($Value) {
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value) -or $Value.Length -gt 20000) { throw 'INVALID_JSON_STRING' }
}

function Assert-TuReview($Review, $Snapshot) {
    Assert-TuFields $Review @('schema_version','commit_sha','parent_sha','files_reviewed','findings','test_results','verdict')
    if ($Review.schema_version -isnot [int] -or $Review.schema_version -ne 1 -or $Review.commit_sha -cnotmatch '^[a-f0-9]{40}$' -or
        ($null -ne $Review.parent_sha -and $Review.parent_sha -cnotmatch '^[a-f0-9]{40}$') -or
        $Review.commit_sha -cne $Snapshot.commit_sha -or $Review.parent_sha -cne $Snapshot.parent_sha -or
        $Review.verdict -cnotin @('PASS','CHANGES_REQUIRED') -or $Review.files_reviewed -isnot [array] -or
        $Review.findings -isnot [array] -or $Review.test_results -isnot [array] -or $Review.files_reviewed.Count -eq 0) { throw 'INVALID_REVIEW_HEADER' }
    $paths = @($Snapshot.files | ForEach-Object { $_.path })
    $reviewedPaths = @{}
    foreach ($p in $Review.files_reviewed) {
        if ($p -isnot [string] -or $p -cnotin $paths -or $reviewedPaths.ContainsKey($p)) { throw 'INVALID_REVIEW_FILE' }
        $reviewedPaths[$p]=$true
    }
    foreach ($p in $Snapshot.changed_files) {
        if (-not (Test-TuReportPath $p) -and $p -cnotin $Review.files_reviewed) { throw 'INCOMPLETE_REVIEW' }
    }
    $ids = @{}
    foreach ($f in $Review.findings) {
        Assert-TuFields $f @('id','severity','confidence','category','file','line','description','evidence','impact','recommended_fix','verification_steps','action','confirmed')
        foreach ($name in @('id','category','file','description','evidence','impact','recommended_fix')) { Assert-TuString $f.$name }
        if ($ids.ContainsKey($f.id)) { throw 'DUPLICATE_FINDING_ID' }; $ids[$f.id] = $true
        if ($f.severity -cnotin @('CRITICAL','HIGH','MEDIUM','LOW') -or $f.action -cnotin @('REQUIRED','OPTIONAL') -or
            $f.confirmed -isnot [bool] -or ($f.confidence -isnot [double] -and $f.confidence -isnot [decimal] -and $f.confidence -isnot [int]) -or
            $f.confidence -lt 0 -or $f.confidence -gt 1 -or $f.line -isnot [int] -or $f.line -lt 1 -or
            $f.file -cnotin $Review.files_reviewed -or $f.verification_steps -isnot [array] -or $f.verification_steps.Count -eq 0) { throw 'INVALID_FINDING' }
        $file = @($Snapshot.files | Where-Object path -CEQ $f.file)[0]
        if ($f.line -gt $file.line_count) { throw 'INVALID_FINDING_LINE' }
        foreach ($step in $f.verification_steps) { Assert-TuString $step }
        if ($f.confirmed -and $f.severity -in @('CRITICAL','HIGH') -and $f.action -ne 'REQUIRED') { throw 'INVALID_SEVERITY_DISPOSITION' }
    }
    foreach ($result in $Review.test_results) { Assert-TuString $result }
    $required = @($Review.findings | Where-Object action -EQ 'REQUIRED')
    if (($Review.verdict -eq 'PASS' -and $required.Count) -or ($Review.verdict -eq 'CHANGES_REQUIRED' -and -not $required.Count)) { throw 'INCONSISTENT_VERDICT' }
    Assert-TuNoSecrets ($Review | ConvertTo-Json -Depth 30)
}
