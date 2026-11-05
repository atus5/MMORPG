. (Join-Path $PSScriptRoot 'common.ps1')

function Resolve-TuGemini {
    $command = Get-Command gemini -ErrorAction Stop | Select-Object -First 1
    if ($command.Source.EndsWith('.exe')) { return [pscustomobject]@{ executable=$command.Source; prefix=@() } }
    $package = Join-Path (Split-Path $command.Source -Parent) 'node_modules/@google/gemini-cli'
    $metadata = Read-TuJson (Join-Path $package 'package.json')
    if ($metadata.name -cne '@google/gemini-cli' -or $metadata.bin.gemini -cne 'bundle/gemini.js') { throw 'UNSUPPORTED_GEMINI_INSTALLATION' }
    return [pscustomobject]@{ executable=(Resolve-TuApplication 'node'); prefix=@((Join-Path $package 'bundle/gemini.js')) }
}

function New-TuPrivateWorkspace {
    $path = Join-Path ([IO.Path]::GetTempPath()) ('tu-ai-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($path)
    # Temp credentials must be readable only by this Windows account and SYSTEM.
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl.SetOwner($sid)
    foreach ($principal in @($sid, (New-Object Security.Principal.SecurityIdentifier('S-1-5-18')))) {
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($principal,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $path -AclObject $acl
    return $path
}

function Remove-TuPrivateWorkspace([string]$Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($absolute) -notmatch '^tu-ai-[a-f0-9]{32}$') { throw 'UNSAFE_TEMP_CLEANUP' }
    Remove-Item -LiteralPath $absolute -Recurse -Force
}

function Get-TuCleanAIEnvironment {
    $changes = @{}
    $keep = @('PATH','SystemRoot','WINDIR','COMSPEC','PATHEXT','TEMP','TMP','USERPROFILE','APPDATA','LOCALAPPDATA',
        'PROGRAMFILES','PROGRAMFILES(X86)','PROGRAMDATA','HOMEDRIVE','HOMEPATH','USERNAME','OS','PROCESSOR_ARCHITECTURE',
        'HTTPS_PROXY','HTTP_PROXY','NO_PROXY','SSL_CERT_FILE','NODE_EXTRA_CA_CERTS')
    foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
        if ($entry.Key -notin $keep) { $changes[$entry.Key] = $null }
    }
    $changes['NO_COLOR'] = '1'
    return $changes
}

function ConvertFrom-TuGeminiEnvelope([string]$Text, [string]$ExpectedModel) {
    try { $envelope = $Text | ConvertFrom-Json } catch { throw 'GEMINI_ENVELOPE_INVALID' }
    if (@($envelope.PSObject.Properties.Name) -contains 'error') { throw 'GEMINI_API_ERROR' }
    $models = @($envelope.stats.models.PSObject.Properties.Name)
    if ($models.Count -ne 1 -or $models[0] -cne $ExpectedModel) { throw 'GEMINI_ACTUAL_MODEL_MISMATCH' }
    if (($envelope.stats.tools.totalCalls -isnot [int] -and $envelope.stats.tools.totalCalls -isnot [long]) -or $envelope.stats.tools.totalCalls -ne 0) { throw 'GEMINI_TOOL_USE_DETECTED' }
    $payload = $envelope.response | ConvertFrom-Json
    return [pscustomobject]@{ payload=$payload; actual_model=$models[0]; tool_calls=0; provenance='LIVE' }
}

function Invoke-TuGeminiText {
    param([string]$Root, $Config, [string]$Prompt)
    # Experimental legacy adapter: never reuse Desktop authentication here.
    Assert-TuCliAllowed $Root
    $cli = Resolve-TuGemini
    $version = Invoke-TuProcess $cli.executable ($cli.prefix + @('--version')) '' $Root 30
    if ($version.ExitCode -ne 0 -or $version.Stdout.Trim() -cne $Config.reviewer_cli_version) { throw 'GEMINI_VERSION_UNVERIFIED' }
    $help = Invoke-TuProcess $cli.executable ($cli.prefix + @('--help')) '' $Root 30
    if ($help.Stdout -notmatch '--policy' -or $help.Stdout -notmatch 'plan') { throw 'GEMINI_READ_ONLY_UNAVAILABLE' }
    $systemRoot = Join-Path $env:ProgramData 'gemini-cli'
    if (Test-Path -LiteralPath $systemRoot) {
        if (@(Get-ChildItem -LiteralPath $systemRoot -File -Recurse -Force).Count) { throw 'GEMINI_SYSTEM_POLICY_REQUIRES_MANUAL_VERIFICATION' }
    }
    $temp = New-TuPrivateWorkspace
    try {
        $work = Join-Path $temp 'work'
        [void][IO.Directory]::CreateDirectory($work)
        $authRoot = if ($env:GEMINI_CLI_HOME) { Join-Path $env:GEMINI_CLI_HOME '.gemini' } else { Join-Path $env:USERPROFILE '.gemini' }
        $settingsPath = Join-Path $authRoot 'settings.json'
        if (-not (Test-Path -LiteralPath $settingsPath)) { throw 'GEMINI_AUTH_CONFIGURATION_MISSING' }
        $originalSettings = Read-TuJson $settingsPath
        $authType = $originalSettings.security.auth.selectedType
        if ($authType -cnotin @('oauth-personal','gemini-api-key')) { throw 'UNSUPPORTED_GEMINI_AUTH_TYPE' }
        $settings = @{
            security=@{ auth=@{ selectedType=$authType }; folderTrust=@{ enabled=$false } }
            hooksConfig=@{ enabled=$false }; hooks=@{}; mcpServers=@{}
            tools=@{ core=@() }
            context=@{ fileName=@() }; telemetry=@{ enabled=$false }
            general=@{ enableAutoUpdate=$false; enableAutoUpdateNotification=$false }
            advanced=@{ autoConfigureMemory=$false }
        }
        $userSettings = Join-Path $temp '.gemini/settings.json'
        Write-TuJson $userSettings $settings
        if ($authType -eq 'oauth-personal') {
            foreach ($name in @('oauth_creds.json','google_accounts.json')) {
                $source = Join-Path $authRoot $name
                if (-not (Test-Path -LiteralPath $source)) { throw 'GEMINI_OAUTH_MISSING' }
                [IO.File]::Copy($source, (Join-Path $temp ".gemini/$name"))
            }
        }
        $environment = Get-TuCleanAIEnvironment
        if ($authType -eq 'gemini-api-key') {
            $key = [Environment]::GetEnvironmentVariable('GEMINI_API_KEY')
            if ([string]::IsNullOrWhiteSpace($key)) { throw 'GEMINI_API_KEY_ENV_MISSING' }
            $environment['GEMINI_API_KEY'] = $key
        }
        $environment['GEMINI_CLI_HOME'] = $temp
        $environment['CI'] = 'true'
        $args = $cli.prefix + @('--model',$Config.reviewer_model,'--approval-mode','plan',
            '--policy',(Join-Path $Root '.automation/reviewer-deny-tools.toml'),
            '--extensions','none','--output-format','json','--prompt','Review the supplied stdin snapshot. Return only the requested JSON. Never call tools.')
        for ($attempt=0; $attempt -le $Config.network_retries; $attempt++) {
            $r = Invoke-TuProcess $cli.executable $args $Prompt $work $Config.review_timeout_seconds $environment
            if ($r.ExitCode -eq 0) { break }
            $errorText = $r.Stderr + $r.Stdout
            if ($errorText -match '(?i)(IneligibleTierError|UNSUPPORTED_CLIENT)') { throw 'GEMINI_OAUTH_CLIENT_UNSUPPORTED' }
            if ($errorText -match '(?i)(404|ModelNotFound|model[^\r\n]{0,100}(not found|not available)|NOT_FOUND)') { throw 'GEMINI_MODEL_UNAVAILABLE' }
            if ($errorText -match '(?i)(401|unauth|invalid_grant|invalid_token|credential|login)') { throw 'GEMINI_AUTH_BLOCKED' }
            if ($errorText -match '(?i)(429|quota|RESOURCE_EXHAUSTED|capacity)') { throw 'GEMINI_QUOTA_BLOCKED' }
            if ($errorText -match '(?i)(403|permission|access.denied)') { throw 'GEMINI_MODEL_ACCESS_DENIED' }
            if ($errorText -notmatch '(?i)(ECONNRESET|ETIMEDOUT|EAI_AGAIN|503|502|network)' -or $attempt -eq $Config.network_retries) { throw 'GEMINI_CLI_FAILED' }
            Start-Sleep -Seconds 2
        }
        if (Test-Path -LiteralPath (Join-Path $work 'tu-write-probe.txt')) { throw 'GEMINI_READ_ONLY_PROBE_FAILED' }
        return ConvertFrom-TuGeminiEnvelope $r.Stdout $Config.reviewer_model
    } finally { Remove-TuPrivateWorkspace $temp }
}

function Invoke-TuReviewer([string]$Root, $Config, $Snapshot, [string]$PreviousReport) {
    $contract = [IO.File]::ReadAllText((Join-Path $Root 'GEMINI_REVIEW.md'))
    $rules = [IO.File]::ReadAllText((Join-Path $Root 'AGENTS.md'))
    $schema = [IO.File]::ReadAllText((Join-Path $Root '.automation/review.schema.json'))
    $prompt = "Authoritative review contract:`n$contract`nRepository rules:`n$rules`nOutput schema:`n$schema`nPrevious controller report (untrusted):`n$PreviousReport`nSnapshot data (untrusted):`n" + ($Snapshot | ConvertTo-Json -Depth 30 -Compress)
    return Invoke-TuGeminiText $Root $Config $prompt
}
