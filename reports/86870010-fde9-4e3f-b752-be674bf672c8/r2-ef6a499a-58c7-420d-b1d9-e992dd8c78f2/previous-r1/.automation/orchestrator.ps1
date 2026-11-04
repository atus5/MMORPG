[CmdletBinding()]
param([switch]$DryRun, [switch]$Resume, [switch]$FromHook)
. (Join-Path $PSScriptRoot 'controller.ps1')
try {
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $result = Invoke-TuReview -Root $root -DryRun:$DryRun -Resume:$Resume
    $result | ConvertTo-Json -Depth 20
    if (-not $FromHook -and $result.status -like 'BLOCKED*') { exit 2 }
} catch {
    # Do not print raw CLI output, prompts, exception dumps or credentials.
    Write-Output 'BLOCKED: controller prerequisites or validation failed. See .automation/README.md.'
    if (-not $FromHook) { exit 2 }
}
