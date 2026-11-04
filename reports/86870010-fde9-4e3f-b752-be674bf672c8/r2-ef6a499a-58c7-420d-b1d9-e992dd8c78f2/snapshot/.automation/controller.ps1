. (Join-Path $PSScriptRoot 'invoke-codex.ps1')

function Save-TuState([string]$Root, $State) {
    $State.updated_at = [DateTimeOffset]::UtcNow.ToString('o')
    Write-TuJson (Join-Path $Root '.agents/state/review-status.json') $State
}

function Publish-TuReport([string]$Root, $State, $Review) {
    $stamp = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(7))
    $lines = New-Object Collections.Generic.List[string]
    $lines.Add('# Tu Tien Online - independent review')
    $lines.Add('')
    foreach ($item in @(
        ('Provenance: ' + $State.provenance), ('Commit SHA: ' + $State.commit_sha),
        ('Parent SHA: ' + $State.parent_sha), ('Chain base SHA: ' + $State.base_sha),
        ('Session ID: ' + $State.session_id), ('Requested model: gemini-4-argon'),
        ('Actual model (CLI metadata): ' + $State.actual_model), ('Review time: ' + $stamp.ToString('o')),
        ('Fix attempts consumed: ' + $State.fix_attempts + '/3'), ('Review attempt: ' + $State.review_attempts),
        ('Verdict: ' + $State.verdict), ('Final status: ' + $State.status), ('Reason: ' + $State.reason))) { $lines.Add($item) }
    if ($State.provenance -eq 'FIXTURE') { $lines.Add('TEST FIXTURE ONLY. This is not a real Gemini review.') }
    if ($null -ne $Review) {
        $lines.Add(''); $lines.Add('## Files reviewed')
        foreach ($path in $Review.files_reviewed) { $lines.Add('- ' + $path) }
        foreach ($action in @('REQUIRED','OPTIONAL')) {
            $lines.Add(''); $lines.Add($(if ($action -eq 'REQUIRED') { '## Required Actions' } else { '## Optional Improvements' }))
            foreach ($f in @($Review.findings | Where-Object action -EQ $action)) {
                $lines.Add(''); $lines.Add(('### {0} - {1} - {2}:{3}' -f $f.id,$f.severity,$f.file,$f.line))
                $lines.Add(('Confidence: {0}; confirmed: {1}; category: {2}' -f $f.confidence,$f.confirmed,$f.category))
                $lines.Add($f.description); $lines.Add('Evidence: ' + $f.evidence); $lines.Add('Impact: ' + $f.impact)
                $lines.Add('Recommended fix: ' + $f.recommended_fix)
                foreach ($step in $f.verification_steps) { $lines.Add('- Verify: ' + $step) }
            }
        }
        $lines.Add(''); $lines.Add('## Reviewer test observations (not controller test execution)')
        foreach ($observation in $Review.test_results) { $lines.Add('- ' + $observation) }
    }
    $lines.Add(''); $lines.Add('## Controller test results')
    foreach ($test in @($State.test_results)) { $lines.Add('- ' + ($test | ConvertTo-Json -Depth 10 -Compress)) }
    if (@($State.fix_responses).Count) {
        $lines.Add(''); $lines.Add('## Developer finding dispositions')
        foreach ($response in $State.fix_responses) { $lines.Add('- ' + ($response | ConvertTo-Json -Depth 10 -Compress)) }
    }
    $text = ($lines -join "`n") + "`n"
    Assert-TuNoSecrets $text
    $stem = $stamp.ToString('yyyy-MM-dd') + '-' + $State.commit_sha
    $history = Join-Path $Root ('reports/' + $stem + '.md')
    if (Test-Path -LiteralPath $history) {
        $history = Join-Path $Root ('reports/' + $stem + '-' + $State.session_id + '-' + [guid]::NewGuid().ToString('N') + '.md')
    }
    [void][IO.Directory]::CreateDirectory((Join-Path $Root 'reports'))
    $stream = [IO.File]::Open($history,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try { $bytes=[Text.Encoding]::UTF8.GetBytes($text); $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
    $archive = [pscustomobject]@{ controller=$State; review=$Review }
    $jsonPath = [IO.Path]::ChangeExtension($history,'.json')
    $stream = [IO.File]::Open($jsonPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try { $bytes=[Text.Encoding]::UTF8.GetBytes(($archive | ConvertTo-Json -Depth 40)); $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
    Write-TuUtf8 (Join-Path $Root 'agentReport.md') $text
    Save-TuState $Root $State
}

function Invoke-TuReview {
    param([string]$Root, [switch]$DryRun, [switch]$Resume, [switch]$Fixture,
          [scriptblock]$Reviewer, [scriptblock]$Fixer, [scriptblock]$TestRunner)
    $Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $config = Get-TuConfig $Root
    $branch = Invoke-TuGit $Root @('branch','--show-current')
    if ($branch -cne $config.allowed_branch) { return [pscustomobject]@{ status='SKIPPED_BRANCH'; branch=$branch } }
    if ($env:TU_AUTOMATION_INTERNAL -eq '1') { return [pscustomobject]@{ status='SKIPPED_INTERNAL' } }
    if ($Fixture) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root '.tu-automation-fixture')) -or
            (Invoke-TuGit $Root @('remote')).Length -ne 0) { throw 'FIXTURE_REQUIRES_ISOLATED_REPOSITORY' }
    } elseif ($Reviewer -or $Fixer -or $TestRunner) { throw 'CUSTOM_ENGINES_FORBIDDEN_IN_LIVE_MODE' }
    if (-not $Reviewer) { $Reviewer = { param($r,$c,$s,$p) Invoke-TuReviewer $r $c $s $p } }
    if (-not $Fixer) { $Fixer = { param($r,$c,$s,$v) Invoke-TuFixer $r $c $s $v } }
    if (-not $TestRunner) { $TestRunner = { param($r,$c) Invoke-TuTests $r $c } }
    $commit = Invoke-TuGit $Root @('rev-parse','HEAD')
    $parents = (Invoke-TuGit $Root @('rev-list','--parents','-n','1',$commit)) -split ' '
    if ($parents.Count -gt 2) { throw 'MERGE_COMMIT_REQUIRES_MANUAL_REVIEW' }
    $parent = if ($parents.Count -eq 2) { $parents[1] } else { $null }
    $base = if ($parent) { $parent } else { '4b825dc642cb6eb9a060e54bf8d69288fbee4904' }
    $changes = @(Get-TuChanges $Root $base $commit)
    if (-not @($changes | Where-Object { -not (Test-TuReportPath $_) }).Count) { return [pscustomobject]@{ status='SKIPPED_REPORT_ONLY'; commit_sha=$commit } }
    if ($DryRun) {
        return [pscustomobject]@{ status='DRY_RUN'; enabled=(Test-TuEnabled $Root); branch=$branch; commit_sha=$commit; parent_sha=$parent;
            changed_files=$changes; model=$config.reviewer_model; auto_fix=$config.auto_fix; max_fix_attempts=$config.max_fix_attempts;
            test_commands_configured=$config.test_commands.Count; hooks_modified=$false; ai_called=$false }
    }
    if (-not $Fixture -and -not (Test-TuEnabled $Root)) { return [pscustomobject]@{ status='DISABLED'; commit_sha=$commit } }
    if (-not $Fixture) { Assert-TuActivation $Root }
    $stateDir = Join-Path $Root '.agents/state'
    [void][IO.Directory]::CreateDirectory($stateDir)
    $lockPath = Join-Path $stateDir 'review-lock.json'
    try { $lock = [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
    catch [IO.IOException] { return [pscustomobject]@{ status='SKIPPED_LOCKED'; commit_sha=$commit } }
    $state = $null
    $review = $null
    try {
        $statePath = Join-Path $stateDir 'review-status.json'
        $old = if (Test-Path -LiteralPath $statePath) { Read-TuJson $statePath } else { $null }
        $markerPath = Join-Path $stateDir 'last-reviewed-commit.txt'
        $lastReviewed = if (Test-Path -LiteralPath $markerPath) { [IO.File]::ReadAllText($markerPath).Trim() } else { '' }
        if ($lastReviewed -eq $commit -and ($null -eq $old -or $old.status -ne 'PASS' -or $old.commit_sha -ne $commit)) { throw 'REVIEW_MARKER_STATE_INCONSISTENT' }
        if ($null -ne $old -and $old.status -ne 'PREPARED') {
            if ($old.status -eq 'PASS' -and $old.commit_sha -eq $commit) { return [pscustomobject]@{ status='SKIPPED_DUPLICATE'; commit_sha=$commit } }
            if ($old.status -ne 'PASS') {
                if (-not $Resume) { return [pscustomobject]@{ status='BLOCKED_PENDING_SESSION'; session_id=$old.session_id } }
                if ($old.commit_sha -ne $commit) { [void](Invoke-TuGit $Root @('merge-base','--is-ancestor',$old.commit_sha,$commit)) }
                $state = $old
                $base = $old.base_sha
                $state.commit_sha = $commit
                $state.parent_sha = $parent
            }
        }
        if ($null -eq $state) {
            $state = [pscustomobject]@{ schema_version=1; session_id=[guid]::NewGuid().ToString('N'); original_commit_sha=$commit;
                commit_sha=$commit; parent_sha=$parent; base_sha=$base; fix_attempts=0; review_attempts=0;
                status='IN_PROGRESS'; phase='STARTING'; verdict=$null; actual_model=$null; reason='STARTING';
                provenance=$(if ($Fixture) { 'FIXTURE' } else { 'LIVE' }); test_results=@(); tested_commit=$null; fix_responses=@();
                updated_at=[DateTimeOffset]::UtcNow.ToString('o') }
        }
        $lockInfo = @{ pid=$PID; process_start=[Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().ToString('o'); session_id=$state.session_id; active=$true }
        $bytes=[Text.Encoding]::UTF8.GetBytes(($lockInfo | ConvertTo-Json -Compress)); $lock.SetLength(0); $lock.Write($bytes,0,$bytes.Length); $lock.Flush()
        Assert-TuClean $Root
        Save-TuState $Root $state
        while ($true) {
            if (-not $Fixture -and -not (Test-TuEnabled $Root)) { throw 'AUTOMATION_DISABLED_DURING_SESSION' }
            if ((Invoke-TuGit $Root @('branch','--show-current')) -cne 'tu' -or (Invoke-TuGit $Root @('rev-parse','HEAD')) -ne $state.commit_sha) { throw 'REPOSITORY_CHANGED_DURING_SESSION' }
            Assert-TuClean $Root
            $state.status='IN_PROGRESS'; $state.phase='REVIEWING'; $state.reason='REVIEWING'; $state.verdict=$null; $state.actual_model=$null; $review=$null
            $state.review_attempts++
            Save-TuState $Root $state
            Write-Host ('Review attempt {0}; fix budget {1}/{2}; commit {3}' -f $state.review_attempts,$state.fix_attempts,$config.max_fix_attempts,$state.commit_sha)
            $snapshot = New-TuSnapshot $Root $config $state.base_sha $state.commit_sha $state.parent_sha
            $previousReport = if (Test-Path -LiteralPath (Join-Path $Root 'agentReport.md')) { [IO.File]::ReadAllText((Join-Path $Root 'agentReport.md')) } else { '' }
            $engine = & $Reviewer $Root $config $snapshot $previousReport
            if ($engine.actual_model -cne $config.reviewer_model -or $engine.tool_calls -ne 0 -or
                ($Fixture -and $engine.provenance -cne 'FIXTURE') -or (-not $Fixture -and $engine.provenance -cne 'LIVE')) { throw 'REVIEW_ENGINE_IDENTITY_INVALID' }
            $state.actual_model=$engine.actual_model
            Assert-TuReview $engine.payload $snapshot
            $review = $engine.payload
            $state.verdict=$review.verdict
            if ((Invoke-TuGit $Root @('rev-parse','HEAD')) -ne $state.commit_sha) { throw 'REPOSITORY_CHANGED_DURING_SESSION' }
            Assert-TuClean $Root
            if (@($review.findings | Where-Object severity -EQ 'CRITICAL').Count) { throw 'CRITICAL_REQUIRES_PRODUCT_OWNER' }
            if ($review.verdict -eq 'PASS') {
                if ($state.tested_commit -ne $state.commit_sha) {
                    $tests = & $TestRunner $Root $config
                    $state.test_results=@($tests.results)
                    if ($tests.passed -isnot [bool] -or -not $tests.passed) { throw 'PROJECT_TESTS_FAILED' }
                    $state.tested_commit=$state.commit_sha
                }
                Assert-TuClean $Root
                if ((Invoke-TuGit $Root @('rev-parse','HEAD')) -ne $state.commit_sha) { throw 'REPOSITORY_CHANGED_DURING_SESSION' }
                $state.status='PASS'; $state.phase='COMPLETE'; $state.reason='VALID_REVIEW_AND_TESTS_PASSED'
                Publish-TuReport $Root $state $review
                Write-TuUtf8 (Join-Path $stateDir 'last-reviewed-commit.txt') ($state.commit_sha+"`n")
                return $state
            }
            $state.phase='CHANGES_REQUIRED'; $state.reason='REQUIRED_ACTIONS_REMAIN'
            Publish-TuReport $Root $state $review
            if (-not $config.auto_fix) { throw 'AUTO_FIX_DISABLED' }
            if ($config.test_commands.Count -eq 0 -and -not $Fixture) { throw 'PROJECT_TEST_COMMANDS_MISSING' }
            $required = @($review.findings | Where-Object action -EQ 'REQUIRED')
            if (@($required | Where-Object { -not $_.confirmed -or $_.confidence -lt $config.minimum_fix_confidence -or $_.severity -notin @('HIGH','MEDIUM') }).Count) { throw 'FINDINGS_REQUIRE_OWNER_TRIAGE' }
            if ($state.fix_attempts -ge $config.max_fix_attempts) { throw 'FIX_ATTEMPTS_EXHAUSTED' }
            $state.fix_attempts++; $state.phase='FIXING'; $state.reason='FIXING'
            Save-TuState $Root $state
            if (-not $Fixture -and -not (Test-TuEnabled $Root)) { throw 'AUTOMATION_DISABLED_DURING_SESSION' }
            $fix = & $Fixer $Root $config $snapshot $review
            Assert-TuClean $Root
            if ((Invoke-TuGit $Root @('branch','--show-current')) -cne 'tu' -or (Invoke-TuGit $Root @('rev-parse','HEAD')) -ne $state.commit_sha) { throw 'REPOSITORY_CHANGED_DURING_SESSION' }
            $paths = @(Apply-TuFix $Root $config $review $fix)
            $state.fix_responses=@($fix.finding_responses)
            if ($paths.Count -eq 0) { throw 'NO_FIX_PROPOSED_REQUIRES_OWNER' }
            $state.phase='TESTING'; Save-TuState $Root $state
            $tests = & $TestRunner $Root $config
            $state.test_results=@($tests.results)
            if ($tests.passed -isnot [bool] -or -not $tests.passed) { throw 'PROJECT_TESTS_FAILED' }
            # Tests cannot quietly change protected files or add files outside the proposal.
            $dirty = Invoke-TuGit $Root @('status','--porcelain=v1','-z','--untracked-files=all')
            foreach ($entry in ($dirty -split "`0" | Where-Object { $_ })) {
                $path=$entry.Substring(3)
                if (-not (Test-TuReportPath $path) -and $path -cnotin $paths) { throw 'UNEXPECTED_FILE_CHANGE' }
            }
            if ((Invoke-TuGit $Root @('branch','--show-current')) -cne 'tu' -or (Invoke-TuGit $Root @('rev-parse','HEAD')) -ne $state.commit_sha) { throw 'REPOSITORY_CHANGED_DURING_SESSION' }
            [void](Invoke-TuGit $Root (@('add','--') + $paths))
            $staged = @( (Invoke-TuGit $Root @('diff','--cached','--name-only','-z')) -split "`0" | Where-Object { $_ })
            if ($staged.Count -eq 0 -or @($staged | Where-Object { $_ -cnotin $paths }).Count) { throw 'UNEXPECTED_STAGED_CHANGE' }
            foreach ($path in $staged) { Assert-TuEditablePath $Root $config $path }
            $state.phase='COMMITTING'; Save-TuState $Root $state
            if (-not $Fixture -and -not (Test-TuEnabled $Root)) { throw 'AUTOMATION_DISABLED_DURING_SESSION' }
            $previousInternal = $env:TU_AUTOMATION_INTERNAL
            try {
                $env:TU_AUTOMATION_INTERNAL='1'
                [void](Invoke-TuGit $Root @('commit','-m',('fix: address independent review ['+$state.session_id+' round '+$state.fix_attempts+']')))
            } finally { $env:TU_AUTOMATION_INTERNAL=$previousInternal }
            $newCommit=Invoke-TuGit $Root @('rev-parse','HEAD')
            $newParent=Invoke-TuGit $Root @('rev-parse','HEAD^')
            if ($newCommit -eq $state.commit_sha -or $newParent -ne $state.commit_sha) { throw 'INVALID_FIX_COMMIT' }
            $state.parent_sha=$state.commit_sha; $state.commit_sha=$newCommit; $state.tested_commit=$newCommit
            $state.phase='FIX_COMMITTED'; Save-TuState $Root $state
        }
    } catch {
        $code=$_.Exception.Message
        if ($code -notmatch '^[A-Z][A-Z0-9_]+$') { $code='CONTROLLER_ERROR' }
        if ($null -ne $state) {
            $state.status='BLOCKED'; $state.phase='STOPPED'; $state.reason=$code
            Publish-TuReport $Root $state $review
            Write-Warning ('BLOCKED: '+$code+'; inspect agentReport.md. Product Owner action required.')
            return $state
        }
        throw $code
    } finally {
        try { $bytes=[Text.Encoding]::UTF8.GetBytes('{"active":false}'); $lock.SetLength(0); $lock.Position=0; $lock.Write($bytes,0,$bytes.Length); $lock.Flush() }
        finally { $lock.Dispose() }
    }
}
