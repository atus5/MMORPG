[CmdletBinding()]
param()
# No AI client, Git command, commit, activation, report or history write is used.
. (Join-Path $PSScriptRoot '../invoke-codex.ps1')
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$script:nativeCalls = 0
$script:resolutionCalls = 0

# Tripwires ensure a missing guard cannot accidentally invoke a real AI client.
function Resolve-TuApplication { $script:resolutionCalls++; throw 'UNEXPECTED_CLI_RESOLUTION' }
function Resolve-TuGemini { $script:resolutionCalls++; throw 'UNEXPECTED_CLI_RESOLUTION' }
function Invoke-TuProcess { $script:nativeCalls++; throw 'UNEXPECTED_PROCESS_EXECUTION' }

function Assert-DesktopCheck([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-DesktopBlocked([scriptblock]$Action) {
    $blocked = $false
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -cne 'CLI_DISABLED_DESKTOP_ONLY') { throw }
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
    foreach ($file in @('agentReport.md','.git/HEAD','.git/index','.git/config')) {
        $path = Join-Path $Root $file
        if (Test-Path -LiteralPath $path) { $records += $path + ':' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    }
    return (($records | Sort-Object) -join "`n")
}

$before = Get-DesktopHistoryHashes $projectRoot
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$fixtureRoot = Join-Path $tempRoot ('tu-desktop-policy-' + [guid]::NewGuid().ToString('N'))
$passed = 0
try {
    Write-TuUtf8 (Join-Path $fixtureRoot '.automation/DESKTOP_ONLY') 'Desktop policy fixture'
    # A stale enabled record must not override the current Desktop-only boundary.
    Write-TuJson (Join-Path $fixtureRoot '.agents/state/activation.json') @{
        enabled=$true; product_owner_approved=$true; fingerprint='old-activation'
    }
    Assert-DesktopCheck (-not (Test-TuEnabled $projectRoot)) 'The actual repository must remain disabled.'
    $passed++; Write-Host 'PASS: repository CLI activation is disabled'
    Assert-DesktopCheck (-not (Test-TuEnabled $fixtureRoot)) 'An old activation record bypassed Desktop policy.'
    $passed++; Write-Host 'PASS: Desktop policy overrides a stale enabled record'
    Assert-DesktopBlocked { Assert-TuCliAllowed $fixtureRoot }
    $passed++; Write-Host 'PASS: CLI policy rejects live operations'
    Assert-DesktopBlocked { Invoke-TuCodexText $fixtureRoot $null 'Never sent to a client' }
    $passed++; Write-Host 'PASS: Codex adapter stops before resolution or execution'
    Assert-DesktopBlocked { Invoke-TuGeminiText $fixtureRoot $null 'Never sent to a client' }
    $passed++; Write-Host 'PASS: Gemini adapter stops before resolution, authentication or execution'
    Assert-DesktopCheck ($script:nativeCalls -eq 0 -and $script:resolutionCalls -eq 0) 'A client/process was reached.'
    Assert-DesktopCheck ((Get-DesktopHistoryHashes $projectRoot) -ceq $before) 'Report/state/Git history changed.'
    Write-Output ('Desktop policy checks passed: {0}; CLI resolutions: 0; process calls: 0; report/state/Git files unchanged.' -f $passed)
} finally {
    # Remove only this test's exact files, then empty directories; never recurse.
    $absolute = [IO.Path]::GetFullPath($fixtureRoot)
    if (-not $absolute.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($absolute) -notmatch '^tu-desktop-policy-[a-f0-9]{32}$') { throw 'UNSAFE_FIXTURE_CLEANUP' }
    foreach ($relative in @('.automation/DESKTOP_ONLY','.agents/state/activation.json')) {
        $path = Join-Path $absolute $relative
        if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
    }
    foreach ($relative in @('.agents/state','.agents','.automation')) {
        $path = Join-Path $absolute $relative
        if ([IO.Directory]::Exists($path)) { [IO.Directory]::Delete($path,$false) }
    }
    if ([IO.Directory]::Exists($absolute)) { [IO.Directory]::Delete($absolute,$false) }
}
