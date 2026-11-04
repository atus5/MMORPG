[CmdletBinding()]
param()
# No AI client or Git mutation. Negative child tests run only in fresh temp copies.
. (Join-Path $PSScriptRoot '../invoke-codex.ps1')
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Assert-TuDesktopPolicy $projectRoot
$markerHash = (Get-FileHash -LiteralPath (Join-Path $projectRoot '.automation/DESKTOP_ONLY')).Hash
$script:runTestProcess = ${function:Invoke-TuProcess}
$script:nativeCalls = 0
$script:resolutionCalls = 0

# Tripwires ensure a missing guard cannot accidentally invoke a real AI client.
function Resolve-TuApplication { $script:resolutionCalls++; throw 'UNEXPECTED_CLI_RESOLUTION' }
function Resolve-TuGemini { $script:resolutionCalls++; throw 'UNEXPECTED_CLI_RESOLUTION' }
function Invoke-TuProcess { $script:nativeCalls++; throw 'UNEXPECTED_PROCESS_EXECUTION' }

function Assert-DesktopCheck([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-DesktopBlocked([scriptblock]$Action, [string]$Code='CLI_DISABLED_DESKTOP_ONLY') {
    $blocked = $false
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -cne $Code) { throw }
        $blocked = $true
    }
    Assert-DesktopCheck $blocked 'Expected the Desktop-only policy to stop this operation.'
}
function Get-DesktopHistoryHashes([string]$Root) {
    $records = @()
    foreach ($folder in @('.agents/state','reports')) {
        $path = Join-Path $Root $folder
        if (Test-Path -LiteralPath $path) {
            $records += @(Get-ChildItem -LiteralPath $path -File -Recurse -Force | ForEach-Object {
                $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            })
        }
    }
    foreach ($file in @('agentReport.md','.git/HEAD','.git/refs/heads/tu','.git/index','.git/config')) {
        $path = Join-Path $Root $file
        if (Test-Path -LiteralPath $path) { $records += $path + ':' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    }
    return (($records | Sort-Object) -join "`n")
}

$before = Get-DesktopHistoryHashes $projectRoot
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$fixtureRoot = Join-Path $tempRoot ('tu-desktop-policy-' + [guid]::NewGuid().ToString('N'))
$copied = @('.automation/common.ps1','.automation/invoke-codex.ps1','.automation/invoke-gemini.ps1',
    '.automation/config.json','.automation/DESKTOP_ONLY','.automation/tests/desktop-policy.tests.ps1',
    'AGENTS.md','GEMINI_REVIEW.md','DESKTOP_WORKFLOW.md','README.md','.gitignore')
$passed = 0
try {
    $passed++; Write-Host 'PASS: actual project marker exists and has exactly the expected content'
    Assert-DesktopBlocked { Assert-TuCliAllowed $projectRoot }
    $passed++; Write-Host 'PASS: actual project blocks CLI operations'
    Assert-DesktopBlocked { Invoke-TuCodexText $projectRoot $null 'Never sent to a client' }
    $passed++; Write-Host 'PASS: actual project Codex adapter stops before client discovery'
    Assert-DesktopBlocked { Invoke-TuGeminiText $projectRoot $null 'Never sent to a client' }
    $passed++; Write-Host 'PASS: actual project Gemini adapter stops before client discovery or authentication'
    foreach ($relative in $copied) {
        $target = Join-Path $fixtureRoot $relative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        [IO.File]::Copy((Join-Path $projectRoot $relative),$target,$false)
    }
    # A stale enabled record must not override the current Desktop-only boundary.
    Write-TuJson (Join-Path $fixtureRoot '.agents/state/activation.json') @{
        enabled=$true; product_owner_approved=$true; fingerprint='old-activation'
    }
    Assert-DesktopCheck (-not (Test-TuEnabled $fixtureRoot)) 'An old activation record bypassed Desktop policy.'
    $passed++; Write-Host 'PASS: Desktop policy overrides a stale enabled record'
    $absolute = [IO.Path]::GetFullPath($fixtureRoot)
    Assert-DesktopCheck ($absolute.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($absolute) -match '^tu-desktop-policy-[a-f0-9]{32}$' -and $absolute -ne $projectRoot) 'Unsafe negative fixture'
    $marker = Join-Path $fixtureRoot '.automation/DESKTOP_ONLY'
    $exe = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $testFile = Join-Path $fixtureRoot '.automation/tests/desktop-policy.tests.ps1'
    [IO.File]::Delete($marker)
    $child = & $script:runTestProcess $exe @('-NoProfile','-File',$testFile) '' $fixtureRoot 30
    Assert-DesktopCheck ($child.ExitCode -ne 0 -and $child.Stderr.Contains('DESKTOP_POLICY_MISSING') -and $child.Stdout -notmatch 'checks passed') 'Missing-marker test incorrectly passed'
    $passed++; Write-Host 'PASS: whole test fails when its isolated project marker is missing'
    Write-TuUtf8 $marker 'unexpected policy content'
    $child = & $script:runTestProcess $exe @('-NoProfile','-File',$testFile) '' $fixtureRoot 30
    Assert-DesktopCheck ($child.ExitCode -ne 0 -and $child.Stderr.Contains('DESKTOP_POLICY_INVALID') -and $child.Stdout -notmatch 'checks passed') 'Corrupt-marker test incorrectly passed'
    $passed++; Write-Host 'PASS: whole test fails when its isolated project marker is corrupt'
    Assert-DesktopBlocked { Invoke-TuCodexText $fixtureRoot $null '' } 'DESKTOP_POLICY_INVALID'
    Assert-DesktopBlocked { Invoke-TuGeminiText $fixtureRoot $null '' } 'DESKTOP_POLICY_INVALID'
    $passed++; Write-Host 'PASS: corrupt marker blocks both adapters before client calls'
    [IO.File]::Copy((Join-Path $projectRoot '.automation/DESKTOP_ONLY'),$marker,$true)
    $fingerprint = Get-TuFingerprint $fixtureRoot
    foreach ($relative in @('DESKTOP_WORKFLOW.md','GEMINI_REVIEW.md')) {
        $path = Join-Path $fixtureRoot $relative
        [IO.File]::AppendAllText($path,"`nFixture policy mutation")
        Assert-DesktopCheck ((Get-TuFingerprint $fixtureRoot) -cne $fingerprint) ('Fingerprint missed '+$relative)
        [IO.File]::Copy((Join-Path $projectRoot $relative),$path,$true)
        $passed++; Write-Host ('PASS: fingerprint detects changes to '+$relative)
    }
    [IO.File]::Delete((Join-Path $fixtureRoot 'DESKTOP_WORKFLOW.md'))
    Assert-DesktopCheck ((Get-TuFingerprint $fixtureRoot) -cne $fingerprint) 'Fingerprint missed missing workflow'
    $passed++; Write-Host 'PASS: fingerprint detects missing Desktop workflow'
    Assert-DesktopCheck (-not (Test-TuEnabled $projectRoot)) 'Actual repository became enabled'
    Assert-DesktopCheck ($script:nativeCalls -eq 0 -and $script:resolutionCalls -eq 0) 'A client/process was reached.'
    Assert-DesktopCheck ((Get-FileHash -LiteralPath (Join-Path $projectRoot '.automation/DESKTOP_ONLY')).Hash -ceq $markerHash) 'Actual marker changed'
    Assert-DesktopCheck ((Get-DesktopHistoryHashes $projectRoot) -ceq $before) 'Report/state/Git history changed.'
    Write-Output ('Desktop policy checks passed: {0}; AI client resolutions: 0; AI process calls: 0; isolated negative child tests: 2; actual marker/history unchanged.' -f $passed)
} finally {
    # Remove only this test's exact files, then empty directories; never recurse.
    $absolute = [IO.Path]::GetFullPath($fixtureRoot)
    if (-not $absolute.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($absolute) -notmatch '^tu-desktop-policy-[a-f0-9]{32}$') { throw 'UNSAFE_FIXTURE_CLEANUP' }
    foreach ($relative in ($copied + '.agents/state/activation.json')) {
        $path = Join-Path $absolute $relative
        if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
    }
    foreach ($relative in @('.automation/tests','.agents/state','.agents','.automation')) {
        $path = Join-Path $absolute $relative
        if ([IO.Directory]::Exists($path)) { [IO.Directory]::Delete($path,$false) }
    }
    if ([IO.Directory]::Exists($absolute)) { [IO.Directory]::Delete($absolute,$false) }
}
