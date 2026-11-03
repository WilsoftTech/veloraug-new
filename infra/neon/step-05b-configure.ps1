<#
Configures the Neon development branch for Step 5B. The owner runs this.

It uses the owner's own Neon sign-in and handles no secrets. It changes only the
development branch, apart from creating that branch from production, which does
not alter production. It runs no migration.

  -Phase Branch  Creates the branch, sets up email sign-in, and writes the Auth URL
                 to apps/auth_pages/.env.local. Run this before deploying the pages.
  -Phase OAuth   Adds the trusted domain, protected resource and two public OAuth
                 clients, and writes apps/client/dart_defines.local.json. Run this
                 after the pages are deployed.
  -DryRun        Prints the commands that change something, and runs none of them.
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('Branch', 'OAuth')][string]$Phase,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$ProjectId = 'round-block-80526448'
$Parent = 'production'
$Branch = 'development'
$PagesUrl = 'https://veloraug-auth-dev.pages.dev'
$Resource = 'https://api-dev.veloraug.invalid'
$WebCallback = 'http://localhost:8765/auth.html'
$AndroidCallback = "$PagesUrl/auth/callback/android"
$WebClientName = 'VeloraUG Web Dev'
$AndroidClientName = 'VeloraUG Android Dev'

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$PagesEnvFile = Join-Path $RepoRoot 'apps\auth_pages\.env.local'
$DartDefinesFile = Join-Path $RepoRoot 'apps\client\dart_defines.local.json'

function Invoke-Neon {
    param([string[]]$NeonArgs, [switch]$Changes)

    $all = $NeonArgs + @('--project-id', $ProjectId)
    if ($Changes -and $DryRun) {
        Write-Host "[dry run] neon $($all -join ' ')"
        return ''
    }
    $output = & npx --yes neon@8.17.1 @all
    if ($LASTEXITCODE -ne 0) {
        throw "This Neon command failed, and nothing after it was run: neon $($all -join ' ')"
    }
    return ($output -join "`n")
}

function Write-TextFile {
    param([string]$Path, [string]$Text)

    if ($DryRun) {
        Write-Host "[dry run] would write $Path"
        return
    }
    # Without a byte order mark, which the tools reading these files may reject.
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Wrote $Path"
}

function Get-AuthUrl {
    $status = Invoke-Neon @('neon-auth', 'status', '--branch', $Branch)
    if ($status -match 'Base URL:\s+(\S+)') { return $Matches[1] }
    throw 'Could not read the Auth URL. Is Auth enabled on the development branch?'
}

function New-PublicClient {
    param([string]$Name, [string]$Callback)

    $json = Invoke-Neon -Changes @(
        'neon-auth', 'oauth-client', 'create',
        '--name', $Name,
        '--type', 'public',
        '--redirect-uris', $Callback,
        '--resources', $Resource,
        '--branch', $Branch,
        '--output', 'json'
    )
    if ($DryRun) { return 'DRY_RUN_CLIENT_ID' }
    $client = $json | ConvertFrom-Json
    if (-not $client.client_id) {
        throw "Client '$Name' was created, but its ID was not in the reply. Read it with: neon neon-auth oauth-client list"
    }
    return $client.client_id
}

$branches = Invoke-Neon @('branches', 'list')

if ($Phase -eq 'Branch') {
    if ($branches -match "(?m)\b$Branch\b") {
        Write-Host "The $Branch branch already exists, so it was not created."
    }
    else {
        Invoke-Neon -Changes @('branches', 'create', '--name', $Branch, '--parent', $Parent) | Out-Null
        if (-not $DryRun) { Write-Host "Created the $Branch branch from $Parent." }
    }

    if ($DryRun -and $branches -notmatch "(?m)\b$Branch\b") {
        Write-Host '[dry run] would read the Auth URL from the new branch, and enable Auth if it is not on.'
        $authUrl = 'https://DRY-RUN.example/neondb/auth'
    }
    else {
        try {
            $authUrl = Get-AuthUrl
        }
        catch {
            Write-Host 'Auth is not on for this branch yet, so enabling it.'
            Invoke-Neon -Changes @('neon-auth', 'enable', '--branch', $Branch) | Out-Null
            $authUrl = Get-AuthUrl
        }
    }

    Invoke-Neon -Changes @(
        'neon-auth', 'config', 'email-password', 'update',
        '--enabled',
        '--require-email-verification',
        '--send-verification-email-on-sign-up',
        '--auto-sign-in-after-verification',
        '--email-verification-method', 'otp',
        '--branch', $Branch
    ) | Out-Null
    Invoke-Neon -Changes @('neon-auth', 'domain', 'allow-localhost', 'enable', '--branch', $Branch) | Out-Null

    Write-TextFile $PagesEnvFile "VITE_NEON_AUTH_URL=$authUrl`n"
    Write-Host "Auth URL for ${Branch}: $authUrl"
    Write-Host 'Next: deploy the pages, as in apps/auth_pages/README.md.'
    return
}

if ($branches -notmatch "(?m)\b$Branch\b") {
    throw "The $Branch branch does not exist. Run -Phase Branch first."
}
$authUrl = Get-AuthUrl

Invoke-Neon -Changes @('neon-auth', 'domain', 'add', $PagesUrl, '--branch', $Branch) | Out-Null
Invoke-Neon -Changes @('neon-auth', 'config', 'oauth-server', 'resource', 'add', $Resource, '--branch', $Branch) | Out-Null
Invoke-Neon -Changes @(
    'neon-auth', 'config', 'oauth-server', 'update',
    '--enabled',
    '--login-page', "$PagesUrl/login",
    '--consent-page', "$PagesUrl/consent",
    '--branch', $Branch
) | Out-Null

# Running this twice would create duplicate clients, so stop if they exist.
if (-not $DryRun) {
    $existing = Invoke-Neon @('neon-auth', 'oauth-client', 'list', '--branch', $Branch)
    if ($existing -match [regex]::Escape($WebClientName) -or $existing -match [regex]::Escape($AndroidClientName)) {
        throw 'The OAuth clients already exist, so none were created. dart_defines.local.json was not changed.'
    }
}

$webClientId = New-PublicClient $WebClientName $WebCallback
$androidClientId = New-PublicClient $AndroidClientName $AndroidCallback

$defines = [ordered]@{
    API_BASE_URL                = 'http://127.0.0.1:8000'
    NEON_AUTH_URL               = $authUrl
    NEON_AUTH_WEB_CLIENT_ID     = $webClientId
    NEON_AUTH_ANDROID_CLIENT_ID = $androidClientId
    API_RESOURCE                = $Resource
    AUTH_PAGES_URL              = $PagesUrl
}
Write-TextFile $DartDefinesFile (($defines | ConvertTo-Json) + "`n")
Write-Host 'Next: run infra/neon/check_step05b.py.'
