[CmdletBinding(DefaultParameterSetName='Plan')]
param([Parameter(ParameterSetName='Enable')][switch]$Enable,
      [Parameter(ParameterSetName='Enable')][switch]$ProductOwnerApproved,
      [Parameter(ParameterSetName='Disable')][switch]$Disable,
      [Parameter(ParameterSetName='Uninstall')][switch]$Uninstall)
. (Join-Path $PSScriptRoot 'invoke-codex.ps1')
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ($Enable) { Assert-TuCliAllowed $root }
$config = Get-TuConfig $root
$git = Resolve-TuApplication 'git'
$current = Invoke-TuProcess $git @('config','--local','--get','core.hooksPath') '' $root 30
$hookPath = $current.Stdout.Trim()
if ($Enable) {
    if (-not $ProductOwnerApproved) { throw 'PRODUCT_OWNER_APPROVAL_REQUIRED' }
    if ((Invoke-TuGit $root @('branch','--show-current')) -cne 'tu') { throw 'ONLY_TU_CAN_ENABLE_AUTOMATION' }
    if ($config.test_commands.Count -eq 0) { throw 'PROJECT_TEST_COMMANDS_MISSING' }
    Assert-TuClean $root
    Assert-TuActivation $root
    $tests = Invoke-TuTests $root $config
    if (-not $tests.passed) { throw 'PROJECT_TESTS_FAILED' }
    Assert-TuClean $root
    # Respect effective hooksPath as well as local overrides (global/system may be set).
    $effective = Invoke-TuProcess $git @('config','--get','core.hooksPath') '' $root 30
    if ($effective.ExitCode -eq 0 -and $effective.Stdout.Trim() -cne '.githooks') { throw 'EXISTING_HOOKS_PATH_REQUIRES_MANUAL_INTEGRATION' }
    $legacy = Join-Path $root '.git/hooks/post-commit'
    if (Test-Path -LiteralPath $legacy) { throw 'EXISTING_POST_COMMIT_REQUIRES_MANUAL_INTEGRATION' }
    $installPath = Join-Path $root '.agents/state/hooks-install.json'
    if (-not (Test-Path -LiteralPath $installPath)) {
        Write-TuJson $installPath @{ previous_local_hooks_path=$hookPath; had_local_value=($current.ExitCode -eq 0); approved_at=[DateTimeOffset]::UtcNow.ToString('o') }
    }
    [void](Invoke-TuGit $root @('config','--local','core.hooksPath','.githooks'))
    Write-TuJson (Join-Path $root '.agents/state/activation.json') @{ enabled=$true; product_owner_approved=$true;
        fingerprint=(Get-TuFingerprint $root); approved_at=[DateTimeOffset]::UtcNow.ToString('o') }
    Write-Output 'Enabled: post-commit on tu. No push or merge is performed.'
} elseif ($Disable -or $Uninstall) {
    Write-TuJson (Join-Path $root '.agents/state/activation.json') @{ enabled=$false; product_owner_approved=$false;
        fingerprint=(Get-TuFingerprint $root); disabled_at=[DateTimeOffset]::UtcNow.ToString('o') }
    if ($Uninstall) {
        $installPath=Join-Path $root '.agents/state/hooks-install.json'
        if ($hookPath -cne '.githooks' -or -not (Test-Path -LiteralPath $installPath)) { throw 'HOOK_OWNERSHIP_NOT_VERIFIED' }
        $previous=Read-TuJson $installPath
        if ($previous.had_local_value) { [void](Invoke-TuGit $root @('config','--local','core.hooksPath',$previous.previous_local_hooks_path)) }
        else {
            $unset=Invoke-TuProcess $git @('config','--local','--unset','core.hooksPath') '' $root 30
            if ($unset.ExitCode -ne 0) { throw 'HOOK_UNINSTALL_FAILED' }
        }
    }
    Write-Output 'Disabled. An already running controller must finish or be stopped separately.'
} else {
    [pscustomobject]@{ mode='PLAN_ONLY'; enabled=(Test-TuEnabled $root); current_local_hooks_path=$hookPath;
        proposed_hooks_path='.githooks'; modifies_git=$false; product_owner_approval_required=$true } | ConvertTo-Json
}
