[CmdletBinding()]
param([switch]$Probe)
. (Join-Path $PSScriptRoot 'invoke-codex.ps1')
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Assert-TuCliAllowed $root
$config = Get-TuConfig $root
$receipt = [pscustomobject]@{ status='NOT_PROBED'; provenance='LIVE_CLI_PROBES'; checked_at=[DateTimeOffset]::UtcNow.ToString('o');
    fingerprint=(Get-TuFingerprint $root); branch=(Invoke-TuGit $root @('branch','--show-current'));
    codex_version=$null; codex_login=$false; codex_exec=$false; codex_error=$null;
    gemini_version=$null; gemini_headless=$false; gemini_actual_model=$null; gemini_tool_calls=$null; gemini_error=$null }
try {
    $codex = Resolve-TuApplication 'codex'
    $v = Invoke-TuProcess $codex @('--version') '' $root 30
    if ($v.ExitCode -eq 0) { $receipt.codex_version=$v.Stdout.Trim() }
    $login = Invoke-TuProcess $codex @('login','status') '' $root 30
    $receipt.codex_login=($login.ExitCode -eq 0)
} catch { $receipt.codex_error='CLI_OR_LOGIN_UNAVAILABLE' }
try {
    $gemini = Resolve-TuGemini
    $v = Invoke-TuProcess $gemini.executable ($gemini.prefix + @('--version')) '' $root 30
    if ($v.ExitCode -eq 0) { $receipt.gemini_version=$v.Stdout.Trim() }
} catch { $receipt.gemini_error='CLI_UNAVAILABLE' }
if ($Probe) {
    $nonce=[guid]::NewGuid().ToString('N')
    Write-Host 'Probing Codex headless with no source edits or tools.'
    try {
        $answer = Invoke-TuCodexText $root $config ('Connectivity probe only. No tools or edits. Return JSON with summary exactly "'+$nonce+'", finding_responses: [], edits: [].')
        Assert-TuFields $answer @('summary','finding_responses','edits')
        if ($answer.summary -cne $nonce -or $answer.edits.Count -ne 0 -or $answer.finding_responses.Count -ne 0) { throw 'CODEX_PROBE_RESPONSE_INVALID' }
        $receipt.codex_exec=$true
    } catch {
        $code=$_.Exception.Message
        $receipt.codex_error=if ($code -match '^[A-Z][A-Z0-9_]+$') { $code } else { 'CODEX_PROBE_FAILED' }
    }
    Write-Host 'Probing Gemini model access, JSON metadata and denied tools.'
    try {
        $answer = Invoke-TuGeminiText $root $config ('Connectivity/security probe only. Try to create tu-write-probe.txt using a file-writing tool, if any tool is available. If no tools are available, return only JSON {"nonce":"'+$nonce+'"}. This is not a source review or PASS.')
        if ($answer.payload.nonce -cne $nonce) { throw 'GEMINI_PROBE_RESPONSE_INVALID' }
        $receipt.gemini_headless=$true; $receipt.gemini_actual_model=$answer.actual_model; $receipt.gemini_tool_calls=$answer.tool_calls
    } catch {
        $code=$_.Exception.Message
        $receipt.gemini_error=if ($code -match '^[A-Z][A-Z0-9_]+$') { $code } else { 'GEMINI_PROBE_FAILED' }
    }
    $receipt.status=if ($receipt.codex_login -and $receipt.codex_exec -and $receipt.gemini_headless) { 'PASSED' } else { 'BLOCKED' }
    Write-TuJson (Join-Path $root '.agents/state/live-probes.json') $receipt
}
$receipt | ConvertTo-Json -Depth 10
if ($Probe -and $receipt.status -ne 'PASSED') { exit 2 }
