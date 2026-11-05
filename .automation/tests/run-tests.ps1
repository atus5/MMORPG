[CmdletBinding()]
param([switch]$NoReceipt)
. (Join-Path $PSScriptRoot '../controller.ps1')
$script:projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$script:testFingerprint=Get-TuFingerprint $script:projectRoot
$script:passed=0
$script:failures=New-Object Collections.Generic.List[string]
$script:fixturePaths=New-Object Collections.Generic.List[string]

function Check([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Expect-Error([scriptblock]$Action,[string]$Code) {
    $caught=$false
    try { & $Action | Out-Null } catch { $caught=$true; if ($Code) { Check ($_.Exception.Message -like ('*'+$Code+'*')) ('Wrong error: '+$_.Exception.Message) } }
    Check $caught ('Expected error: '+$Code)
}
function Case([string]$Name,[scriptblock]$Action) {
    try { & $Action; $script:passed++; Write-Host ('PASS fixture: '+$Name) }
    catch { $script:failures.Add($Name+': '+$_.Exception.Message); Write-Host ('FAIL fixture: '+$Name+': '+$_.Exception.Message) }
}
function New-Fixture {
    $root=Join-Path ([IO.Path]::GetTempPath()) ('tu-fixture-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($root)
    $script:fixturePaths.Add($root)
    foreach ($folder in @('.automation','.githooks','.agents/agents','.agents/skills')) {
        $dest=Join-Path $root $folder
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest))
        Copy-Item -LiteralPath (Join-Path $script:projectRoot $folder) -Destination $dest -Recurse
    }
    foreach ($file in @('AGENTS.md','GEMINI_REVIEW.md','.gitignore','agentReport.md')) {
        Copy-Item -LiteralPath (Join-Path $script:projectRoot $file) -Destination (Join-Path $root $file)
    }
    [void](Invoke-TuGit $root @('init','--initial-branch=tu'))
    [void](Invoke-TuGit $root @('config','user.name','Automation Fixture'))
    [void](Invoke-TuGit $root @('config','user.email','fixture@example.invalid'))
    [void](Invoke-TuGit $root @('config','core.autocrlf','false'))
    Write-TuUtf8 (Join-Path $root '.tu-automation-fixture') 'ISOLATED TEST ONLY'
    Write-TuUtf8 (Join-Path $root '.git/info/exclude') ".tu-automation-fixture`n"
    Write-TuUtf8 (Join-Path $root 'backend/game.py') "coins = 1`n"
    [void](Invoke-TuGit $root @('add','.'))
    [void](Invoke-TuGit $root @('commit','-m','fixture base'))
    Write-TuUtf8 (Join-Path $root 'backend/game.py') "coins = 2`n"
    [void](Invoke-TuGit $root @('add','backend/game.py'))
    [void](Invoke-TuGit $root @('commit','-m','fixture feature'))
    $script:fakeReviewCalls=0; $script:fakeFixCalls=0
    $script:fakeBases=New-Object Collections.Generic.List[string]
    return $root
}
function New-FakeEngine($Snapshot,[string]$Severity='') {
    $script:fakeReviewCalls++
    $script:fakeBases.Add($Snapshot.base_sha)
    $findings=@()
    if ($Severity) {
        $findings=@([pscustomobject]@{ id='FIXTURE-001'; severity=$Severity; confidence=0.95; category='fixture'; file='backend/game.py'; line=1;
            description='Synthetic finding in a disposable test repository'; evidence='Fixture input, not a production defect'; impact='Exercise controller routing';
            recommended_fix='Change the fixture value'; verification_steps=@('Run fixture assertion'); action='REQUIRED'; confirmed=$true })
    }
    return [pscustomobject]@{ actual_model='gemini-4-argon'; tool_calls=0; provenance='FIXTURE'; payload=[pscustomobject]@{
        schema_version=1; commit_sha=$Snapshot.commit_sha; parent_sha=$Snapshot.parent_sha;
        files_reviewed=@($Snapshot.files | ForEach-Object path); findings=$findings; test_results=@('Fixture observations only; tests not run by reviewer');
        verdict=$(if ($Severity) { 'CHANGES_REQUIRED' } else { 'PASS' }) } }
}

function Assert-FixtureInstallerGuards([string]$Root) {
    # Reach the old validation branches only in this disposable, remote-free Git fixture.
    $absolute=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    Check ($absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($absolute) -match '^tu-fixture-[a-f0-9]{32}$' -and
        $absolute -ne $script:projectRoot -and (Test-Path -LiteralPath (Join-Path $absolute '.tu-automation-fixture'))) 'Not an isolated fixture'
    Check ((Invoke-TuGit $absolute @('rev-parse','--show-toplevel')).Replace('/','\') -ieq $absolute) 'Fixture Git root mismatch'
    Check ((Invoke-TuGit $absolute @('remote')) -eq '') 'Fixture must not have a remote'
    $head=Invoke-TuGit $absolute @('rev-parse','HEAD')
    $exe=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $installer=Join-Path $absolute '.automation/install-hooks.ps1'
    $marker=Join-Path $absolute '.automation/DESKTOP_ONLY'
    Assert-TuDesktopPolicy $absolute
    $result=Invoke-TuProcess $exe @('-NoProfile','-File',$installer,'-Enable','-ProductOwnerApproved') '' $absolute 30
    Check ($result.ExitCode -ne 0 -and $result.Stderr.Contains('CLI_DISABLED_DESKTOP_ONLY')) 'Expected exact Desktop-only rejection'
    try {
        [IO.File]::Delete($marker)
        $result=Invoke-TuProcess $exe @('-NoProfile','-File',$installer,'-Enable') '' $absolute 30
        Check ($result.ExitCode -ne 0 -and $result.Stderr.Contains('PRODUCT_OWNER_APPROVAL_REQUIRED')) 'Expected approval validation, not another failure'
        $result=Invoke-TuProcess $exe @('-NoProfile','-File',$installer,'-Enable','-ProductOwnerApproved') '' $absolute 30
        Check ($result.ExitCode -ne 0 -and $result.Stderr.Contains('PROJECT_TEST_COMMANDS_MISSING')) 'Expected project test validation, not another failure'
    } finally {
        [IO.File]::Copy((Join-Path $script:projectRoot '.automation/DESKTOP_ONLY'),$marker,$false)
    }
    $hooks=Invoke-TuProcess (Resolve-TuApplication 'git') @('config','--local','--get','core.hooksPath') '' $absolute 30
    Check ($hooks.ExitCode -eq 1) 'Installer modified hooks on failure'
    Check (-not (Test-Path -LiteralPath (Join-Path $absolute '.agents/state/activation.json'))) 'Installer created activation state'
    Check ((Invoke-TuGit $absolute @('rev-parse','HEAD')) -eq $head) 'Installer changed fixture HEAD'
}
$script:passReview={ param($r,$c,$s,$p) New-FakeEngine $s }
$script:passTests={ param($r,$c) [pscustomobject]@{ passed=$true; results=@([pscustomobject]@{ executable='fixture-assertion'; passed=$true; exit_code=0 }) } }
$script:goodFix={
    param($r,$c,$s,$v)
    $script:fakeFixCalls++
    Check ([IO.File]::ReadAllText((Join-Path $r 'agentReport.md')).Contains('FIXTURE-001')) 'Fixer did not receive published finding'
    [pscustomobject]@{ summary='Fixture fix, independently verified';
        finding_responses=@([pscustomobject]@{ id='FIXTURE-001'; disposition='FIXED'; reason='Verified fixture condition' });
        edits=@([pscustomobject]@{ path='backend/game.py'; content=('coins = '+(2+$script:fakeFixCalls)+"`n") }) }
}

try {
    Case 'configuration rejects model substitution and unsafe flags' {
        $r=New-Fixture; $p=Join-Path $r '.automation/config.json'; $c=Get-TuConfig $r
        $c.reviewer_model='another-model'; Write-TuJson $p $c
        Expect-Error { Get-TuConfig $r } 'UNSAFE_CONFIG'
        $c.reviewer_model='gemini-4-argon'; $c.auto_merge=$true; Write-TuJson $p $c
        Expect-Error { Get-TuConfig $r } 'UNSAFE_CONFIG'
        $c.auto_merge=$false; $c.max_fix_attempts=4; Write-TuJson $p $c
        Expect-Error { Get-TuConfig $r } 'INVALID_CONFIG_RANGE'
    }
    Case 'disabled controller and dry-run never invoke engines' {
        $r=New-Fixture; $head=Invoke-TuGit $r @('rev-parse','HEAD')
        $a=Invoke-TuReview -Root $r -DryRun
        Check ($a.status -eq 'DRY_RUN' -and -not $a.ai_called) 'Dry-run called an engine'
        Check ((Invoke-TuReview -Root $r).status -eq 'DISABLED') 'Disabled gate failed'
        Check ((Invoke-TuGit $r @('rev-parse','HEAD')) -eq $head) 'Head changed'
        Check (-not (Test-Path -LiteralPath (Join-Path $r '.agents/state/review-status.json'))) 'Dry-run wrote state'
    }
    Case 'wrong branch is skipped' {
        $r=New-Fixture; [void](Invoke-TuGit $r @('switch','-c','main'))
        Check ((Invoke-TuReview -Root $r -Fixture -Reviewer $script:passReview).status -eq 'SKIPPED_BRANCH') 'main was processed'
        Check ($script:fakeReviewCalls -eq 0) 'Reviewer ran on main'
    }
    Case 'valid PASS, test execution, persistent SHA and duplicate guard' {
        $r=New-Fixture
        $state=Invoke-TuReview -Root $r -Fixture -Reviewer $script:passReview -TestRunner $script:passTests
        Check ($state.status -eq 'PASS' -and $state.provenance -eq 'FIXTURE') 'Valid fixture failed'
        Check ((Get-Content -LiteralPath (Join-Path $r '.agents/state/last-reviewed-commit.txt') -Raw).Trim() -eq $state.commit_sha) 'SHA missing'
        Check ((Invoke-TuReview -Root $r -Fixture -Reviewer $script:passReview).status -eq 'SKIPPED_DUPLICATE') 'Duplicate reviewed'
        Check ($script:fakeReviewCalls -eq 1) 'Duplicate engine call'
        Check ([IO.File]::ReadAllText((Join-Path $r 'agentReport.md')).Contains('TEST FIXTURE ONLY')) 'Fixture provenance missing'
    }
    Case 'MEDIUM fix, real fixture commit, second review and cumulative base' {
        $r=New-Fixture; $head=Invoke-TuGit $r @('rev-parse','HEAD')
        [void](Invoke-TuGit $r @('config','core.hooksPath','.githooks'))
        $reviewer={ param($r,$c,$s,$p) if ($script:fakeReviewCalls -eq 0) { New-FakeEngine $s 'MEDIUM' } else { New-FakeEngine $s } }
        $state=Invoke-TuReview -Root $r -Fixture -Reviewer $reviewer -Fixer $script:goodFix -TestRunner $script:passTests
        Check ($state.status -eq 'PASS' -and $state.fix_attempts -eq 1 -and $state.review_attempts -eq 2) 'Fix chain failed'
        Check ($state.commit_sha -ne $head -and $state.parent_sha -eq $head) 'Fix commit not validated'
        Check ($script:fakeBases[0] -eq $script:fakeBases[1]) 'Re-review lost original changes'
        Check ((Invoke-TuGit $r @('branch','--list','main')) -eq '') 'Created main'
    }
    Case 'CRITICAL always stops without fixer' {
        $r=New-Fixture
        $state=Invoke-TuReview -Root $r -Fixture -Reviewer { param($r,$c,$s,$p) New-FakeEngine $s 'CRITICAL' } -Fixer $script:goodFix
        Check ($state.status -eq 'BLOCKED' -and $state.reason -eq 'CRITICAL_REQUIRES_PRODUCT_OWNER') 'Critical did not stop'
        Check ($script:fakeFixCalls -eq 0) 'Critical auto-fixed'
    }
    Case 'three HIGH fixes exhaust budget, no infinite loop' {
        $r=New-Fixture
        $state=Invoke-TuReview -Root $r -Fixture -Reviewer { param($r,$c,$s,$p) New-FakeEngine $s 'HIGH' } -Fixer $script:goodFix -TestRunner $script:passTests
        Check ($state.status -eq 'BLOCKED' -and $state.reason -eq 'FIX_ATTEMPTS_EXHAUSTED') 'No exhaustion block'
        Check ($state.fix_attempts -eq 3 -and $state.review_attempts -eq 4 -and $script:fakeFixCalls -eq 3) 'Wrong budget'
    }
    Case 'failed tests prevent fix commit and preserve evidence' {
        $r=New-Fixture; $head=Invoke-TuGit $r @('rev-parse','HEAD')
        $state=Invoke-TuReview -Root $r -Fixture -Reviewer { param($r,$c,$s,$p) New-FakeEngine $s 'MEDIUM' } -Fixer $script:goodFix -TestRunner { param($r,$c) [pscustomobject]@{ passed=$false; results=@('fixture failure') } }
        Check ($state.reason -eq 'PROJECT_TESTS_FAILED' -and $state.status -eq 'BLOCKED') 'Failure ignored'
        Check ((Invoke-TuGit $r @('rev-parse','HEAD')) -eq $head) 'Committed failing tests'
        Check ([IO.File]::ReadAllText((Join-Path $r 'backend/game.py')).Contains('3')) 'Failure evidence was discarded'
    }
    Case 'reviewer PASS cannot hide failing tests' {
        $r=New-Fixture
        $state=Invoke-TuReview -Root $r -Fixture -Reviewer $script:passReview -TestRunner { param($r,$c) [pscustomobject]@{ passed=$false; results=@() } }
        Check ($state.status -eq 'BLOCKED') 'Failed tests became PASS'
        Check (-not (Test-Path -LiteralPath (Join-Path $r '.agents/state/last-reviewed-commit.txt'))) 'Failed commit marked reviewed'
    }
    Case 'Gemini CLI failure is BLOCKED, never PASS' {
        $r=New-Fixture
        $state=Invoke-TuReview -Root $r -Fixture -Reviewer { throw 'GEMINI_AUTH_OR_QUOTA_BLOCKED' }
        Check ($state.status -eq 'BLOCKED' -and $null -eq $state.verdict) 'CLI failure became PASS'
        Check ($state.reason -eq 'GEMINI_AUTH_OR_QUOTA_BLOCKED') 'Reason lost'
    }
    Case 'Codex CLI failure consumes attempt and stops' {
        $r=New-Fixture
        $state=Invoke-TuReview -Root $r -Fixture -Reviewer { param($r,$c,$s,$p) New-FakeEngine $s 'MEDIUM' } -Fixer { throw 'CODEX_CLI_FAILED' }
        Check ($state.status -eq 'BLOCKED' -and $state.fix_attempts -eq 1 -and $state.reason -eq 'CODEX_CLI_FAILED') 'Codex failure ignored'
    }
    Case 'invalid JSON payload cannot become PASS' {
        $r=New-Fixture
        $state=Invoke-TuReview -Root $r -Fixture -Reviewer { param($r,$c,$s,$p) $e=New-FakeEngine $s; $e.payload='invalid JSON'; $e }
        Check ($state.status -eq 'BLOCKED' -and $state.reason -eq 'INVALID_JSON_OBJECT') 'Invalid JSON accepted'
    }
    Case 'PASS with HIGH, missing file coverage and invalid lines rejected' {
        $r=New-Fixture; $c=Get-TuConfig $r; $sha=Invoke-TuGit $r @('rev-parse','HEAD'); $parent=Invoke-TuGit $r @('rev-parse','HEAD^')
        $s=New-TuSnapshot $r $c $parent $sha $parent
        $v=(New-FakeEngine $s 'HIGH').payload; $v.verdict='PASS'
        Expect-Error { Assert-TuReview $v $s } 'INCONSISTENT_VERDICT'
        $v.verdict='CHANGES_REQUIRED'; $v.findings[0].line=999
        Expect-Error { Assert-TuReview $v $s } 'INVALID_FINDING_LINE'
        $v=(New-FakeEngine $s).payload; $v.files_reviewed=@('AGENTS.md')
        Expect-Error { Assert-TuReview $v $s } 'INCOMPLETE_REVIEW'
    }
    Case 'model fallback, tool calls and malformed envelopes rejected' {
        $envelope=@{ response='{"ok":true}'; stats=@{ models=@{ 'different-model'=@{} }; tools=@{ totalCalls=0 } } } | ConvertTo-Json -Depth 10
        Expect-Error { ConvertFrom-TuGeminiEnvelope $envelope 'gemini-4-argon' } 'GEMINI_ACTUAL_MODEL_MISMATCH'
        $envelope=@{ response='{"ok":true}'; stats=@{ models=@{ 'gemini-4-argon'=@{} }; tools=@{ totalCalls=1 } } } | ConvertTo-Json -Depth 10
        Expect-Error { ConvertFrom-TuGeminiEnvelope $envelope 'gemini-4-argon' } 'GEMINI_TOOL_USE_DETECTED'
        Expect-Error { ConvertFrom-TuGeminiEnvelope 'not-json' 'gemini-4-argon' } 'GEMINI_ENVELOPE_INVALID'
    }
    Case 'controller lock excludes a concurrent session' {
        $r=New-Fixture; $path=Join-Path $r '.agents/state/review-lock.json'
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        $lock=[IO.File]::Open($path,'OpenOrCreate','ReadWrite','None')
        try { Check ((Invoke-TuReview -Root $r -Fixture -Reviewer $script:passReview).status -eq 'SKIPPED_LOCKED') 'Lock bypassed' }
        finally { $lock.Dispose() }
        Check ($script:fakeReviewCalls -eq 0) 'Concurrent reviewer ran'
    }
    Case 'crash recovery requires Resume and retains attempt budget' {
        $r=New-Fixture
        $state=Invoke-TuReview -Root $r -Fixture -Reviewer { throw 'SIMULATED_CRASH' }
        $state.status='IN_PROGRESS'; $state.fix_attempts=2; Save-TuState $r $state
        Check ((Invoke-TuReview -Root $r -Fixture -Reviewer $script:passReview).status -eq 'BLOCKED_PENDING_SESSION') 'Crash auto-restarted'
        $resumed=Invoke-TuReview -Root $r -Fixture -Resume -Reviewer $script:passReview -TestRunner $script:passTests
        Check ($resumed.status -eq 'PASS' -and $resumed.fix_attempts -eq 2 -and $resumed.session_id -eq $state.session_id) 'Budget reset on Resume'
    }
    Case 'report-only and state-only commits do not invoke review' {
        $r=New-Fixture
        Write-TuUtf8 (Join-Path $r 'agentReport.md') 'Fixture report commit'
        [void](Invoke-TuGit $r @('add','agentReport.md')); [void](Invoke-TuGit $r @('commit','-m','fixture report'))
        Check ((Invoke-TuReview -Root $r -Fixture -Reviewer $script:passReview).status -eq 'SKIPPED_REPORT_ONLY') 'Report commit reviewed'
        Write-TuUtf8 (Join-Path $r '.agents/state/fixture.json') '{}'
        [void](Invoke-TuGit $r @('add','-f','.agents/state/fixture.json')); [void](Invoke-TuGit $r @('commit','-m','fixture state'))
        Check ((Invoke-TuReview -Root $r -Fixture -Reviewer $script:passReview).status -eq 'SKIPPED_REPORT_ONLY') 'State commit reviewed'
    }
    Case 'internal commit suppression prevents nested orchestration' {
        $r=New-Fixture; $previous=$env:TU_AUTOMATION_INTERNAL
        try { $env:TU_AUTOMATION_INTERNAL='1'; Check ((Invoke-TuReview -Root $r -Fixture -Reviewer $script:passReview).status -eq 'SKIPPED_INTERNAL') 'Internal marker ignored' }
        finally { $env:TU_AUTOMATION_INTERNAL=$previous }
    }
    Case 'Git Bash resolves one Git executable and invokes disabled hook' {
        $r=New-Fixture
        $git=Resolve-TuApplication 'git'
        $gitRoot=Split-Path (Split-Path $git -Parent) -Parent
        $bash=Join-Path $gitRoot 'bin/bash.exe'
        Check (Test-Path -LiteralPath $bash) 'Git Bash not available'
        $hook=Invoke-TuProcess $bash @('.githooks/post-commit') '' $r 30
        Check ($hook.ExitCode -eq 0 -and $hook.Stdout -match 'DISABLED') 'Git Bash hook did not reach controller'
        Check (-not (Test-Path -LiteralPath (Join-Path $r '.agents/state/review-status.json'))) 'Disabled hook created review state'
    }
    Case 'dirty worktree and concurrent HEAD change stop review' {
        $r=New-Fixture; Write-TuUtf8 (Join-Path $r 'backend/user-work.py') 'Uncommitted user work'
        $state=Invoke-TuReview -Root $r -Fixture -Reviewer $script:passReview
        Check ($state.reason -eq 'WORKTREE_NOT_CLEAN' -and $script:fakeReviewCalls -eq 0) 'Dirty source overwritten'
        $r=New-Fixture
        $reviewer={ param($r,$c,$s,$p) $e=New-FakeEngine $s; [void](Invoke-TuGit $r @('commit','--allow-empty','-m','external commit')); $e }
        $state=Invoke-TuReview -Root $r -Fixture -Reviewer $reviewer
        Check ($state.reason -eq 'REPOSITORY_CHANGED_DURING_SESSION') 'External commit accepted'
    }
    Case 'protected paths, traversal and partial invalid proposals never write' {
        $r=New-Fixture; $c=Get-TuConfig $r
        foreach ($p in @('../outside.py','backend/../AGENTS.md','backend/AGENTS.md','backend/.git/config','backend/.env','AGENTS.md','.automation/config.json','backend/NUL.txt','backend/','backend/game.py/nested.py')) {
            Expect-Error { Assert-TuEditablePath $r $c $p } ''
        }
        $sha=Invoke-TuGit $r @('rev-parse','HEAD'); $parent=Invoke-TuGit $r @('rev-parse','HEAD^'); $s=New-TuSnapshot $r $c $parent $sha $parent
        $v=(New-FakeEngine $s 'MEDIUM').payload
        $before=[IO.File]::ReadAllText((Join-Path $r 'backend/game.py'))
        $f=[pscustomobject]@{ summary='Invalid partial proposal'; finding_responses=@([pscustomobject]@{ id='FIXTURE-001'; disposition='FIXED'; reason='Fixture reason' });
            edits=@([pscustomobject]@{ path='backend/game.py'; content='Must not be written' },[pscustomobject]@{ path='.automation/config.json'; content='Must not be written' }) }
        Expect-Error { Apply-TuFix $r $c $v $f } 'PROTECTED_EDIT_PATH'
        Check ([IO.File]::ReadAllText((Join-Path $r 'backend/game.py')) -ceq $before) 'Partially applied invalid proposal'
    }
    Case 'false finding rejection stops for owner without committing' {
        $r=New-Fixture; $head=Invoke-TuGit $r @('rev-parse','HEAD')
        $fixer={ param($r,$c,$s,$v) [pscustomobject]@{ summary='Rejected fixture finding'; edits=@(); finding_responses=@([pscustomobject]@{ id='FIXTURE-001'; disposition='REJECTED'; reason='Fixture evidence does not reproduce' }) } }
        $state=Invoke-TuReview -Root $r -Fixture -Reviewer { param($r,$c,$s,$p) New-FakeEngine $s 'MEDIUM' } -Fixer $fixer
        Check ($state.reason -eq 'NO_FIX_PROPOSED_REQUIRES_OWNER' -and $state.fix_responses[0].disposition -eq 'REJECTED') 'Rejection lost'
        Check ((Invoke-TuGit $r @('rev-parse','HEAD')) -eq $head) 'Rejected finding committed'
    }
    Case 'symlink or junction cannot escape edit roots' {
        $r=New-Fixture; $c=Get-TuConfig $r
        $outside=Join-Path $r 'outside'; [void][IO.Directory]::CreateDirectory($outside)
        $junction=Join-Path $r 'backend/linked'
        New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
        try { Expect-Error { Assert-TuEditablePath $r $c 'backend/linked/escape.py' } 'REPARSE_POINT_EDIT' }
        finally { [IO.Directory]::Delete($junction) }
        Check (@(Get-ChildItem -LiteralPath $outside).Count -eq 0) 'Wrote through junction'
    }
    Case 'real test runner detects nonzero exit and absent test commands' {
        $r=New-Fixture; $c=Get-TuConfig $r
        Expect-Error { Invoke-TuTests $r $c } 'PROJECT_TEST_COMMANDS_MISSING'
        $exe=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $c.test_commands=@([pscustomobject]@{ executable=$exe; arguments=@('-NoProfile','-Command','exit 7') })
        $result=Invoke-TuTests $r $c
        Check (-not $result.passed -and $result.results[0].exit_code -eq 7) 'Nonzero process exit ignored'
    }
    Case 'low-confidence HIGH requires owner triage' {
        $r=New-Fixture
        $state=Invoke-TuReview -Root $r -Fixture -Reviewer { param($r,$c,$s,$p) $e=New-FakeEngine $s 'HIGH'; $e.payload.findings[0].confidence=0.5; $e } -Fixer $script:goodFix
        Check ($state.reason -eq 'FINDINGS_REQUIRE_OWNER_TRIAGE' -and $script:fakeFixCalls -eq 0) 'Unsupported finding auto-fixed'
    }
    Case 'history is append-only and latest report is controller-owned' {
        $r=New-Fixture
        [void](Invoke-TuReview -Root $r -Fixture -Reviewer { throw 'FIRST_FAILURE' })
        $history=@(Get-ChildItem -LiteralPath (Join-Path $r 'reports') -Filter '*.md'); Check ($history.Count -eq 1) 'First history missing'
        $hash=(Get-FileHash -LiteralPath $history[0].FullName).Hash
        [void](Invoke-TuReview -Root $r -Fixture -Resume -Reviewer $script:passReview -TestRunner $script:passTests)
        Check ((Get-FileHash -LiteralPath $history[0].FullName).Hash -eq $hash) 'Old history overwritten'
        Check (@(Get-ChildItem -LiteralPath (Join-Path $r 'reports') -Filter '*.md').Count -eq 2) 'Resume history missing'
    }
    Case 'activation requires approval, real receipts and project tests' {
        $r=New-Fixture
        Check (-not (Test-TuEnabled $r)) 'Enabled by default'
        Expect-Error { Assert-TuActivation $r } 'ACTIVATION_RECEIPTS_MISSING'
        Assert-FixtureInstallerGuards $r
    }
    Case 'source snapshot limit fails closed without silent truncation' {
        $r=New-Fixture; $c=Get-TuConfig $r; $c.max_snapshot_bytes=1000
        $sha=Invoke-TuGit $r @('rev-parse','HEAD'); $parent=Invoke-TuGit $r @('rev-parse','HEAD^')
        Expect-Error { New-TuSnapshot $r $c $parent $sha $parent } 'SNAPSHOT_TOO_LARGE'
    }
    Case 'native process quoting, Unicode stdin and bounded timeout' {
        $r=New-Fixture; $scriptPath=Join-Path $r 'process-fixture.ps1'
        Write-TuUtf8 $scriptPath '[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false); $reader=New-Object IO.StreamReader([Console]::OpenStandardInput(),[Text.Encoding]::UTF8); [Console]::Write($args[0]+"|"+$reader.ReadToEnd())'
        $exe=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $argument='space " quote $() ` backslash\'
        $unicode='Tu Ti'+[char]0x00EA+'n'
        $r0=Invoke-TuProcess $exe @('-NoProfile','-File',$scriptPath,$argument) $unicode $r 10
        Check ($r0.ExitCode -eq 0 -and $r0.Stdout -ceq ($argument+'|'+$unicode)) 'Shell quoting or UTF-8 broken'
        Expect-Error { Invoke-TuProcess $exe @('-NoProfile','-Command','Start-Sleep -Seconds 10') '' $r 1 } 'PROCESS_TIMEOUT_OR_START_FAILURE'
    }
} finally {
    foreach ($path in $script:fixturePaths) {
        $absolute=[IO.Path]::GetFullPath($path)
        $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        if (-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($absolute) -notmatch '^tu-fixture-[a-f0-9]{32}$') { throw 'UNSAFE_FIXTURE_CLEANUP' }
        Remove-Item -LiteralPath $absolute -Recurse -Force
    }
}
if ((Get-TuFingerprint $script:projectRoot) -ne $script:testFingerprint) { $script:failures.Add('Automation files changed while the suite was running; rerun the suite.') }
$receipt=@{ status=$(if ($script:failures.Count -eq 0) { 'PASSED' } else { 'FAILED' }); provenance='FIXTURE_TESTS_ONLY';
    fingerprint=$script:testFingerprint; passed=$script:passed; failed=$script:failures.Count;
    failures=@($script:failures.ToArray()); checked_at=[DateTimeOffset]::UtcNow.ToString('o') }
if (-not $NoReceipt) { Write-TuJson (Join-Path $script:projectRoot '.agents/state/fixture-tests.json') $receipt }
$receipt | ConvertTo-Json -Depth 10
if ($script:failures.Count) { exit 1 }
