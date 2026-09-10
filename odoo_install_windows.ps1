[CmdletBinding()]
param(
    [string]$Root = (Join-Path $HOME 'odoo-dev'),
    [string]$OdooVersion = '16.0',
    [int]$OdooPort = 8080,
    [int]$LongpollingPort = 8072,
    [string]$OdooRepo = 'https://github.com/odoo/odoo.git',
    [string]$OdooBranch = '16.0',
    [string]$AxantaRepo = 'https://github.com/burhanghee/ax-addons-16.git',
    [string]$AxantaBranch = '16.0',
    [string]$WhatsappRepo = 'https://github.com/axanta-bs/tu-whatsapp-v16.git',
    [string]$WhatsappBranch = 'main',
    [switch]$Enterprise,
    [switch]$InstallPrerequisites,
    [switch]$SkipAddonRepos,
    [switch]$NoStart,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step([string]$Message) { Write-Host "`n== $Message ==" -ForegroundColor Cyan }
function Show-Help {
    @'
Odoo Windows development environment

Usage:
  .\odoo_install_windows.ps1 [options]

Options:
  -Help                    Show this help and exit.
  -InstallPrerequisites    Install only missing Git, Python 3.10, PostgreSQL 14,
                           and Node.js LTS packages with winget.
  -Root <path>             Installation root. Default: $HOME\odoo-dev
  -OdooVersion <version>   Odoo directory suffix. Default: 16.0
  -OdooBranch <branch>     Odoo Git branch. Default: 16.0
  -OdooPort <port>         HTTP port. Default: 8069
  -LongpollingPort <port>  Gevent/longpolling port. Default: 8072
  -SkipAddonRepos          Do not clone/update the Axanta and WhatsApp repositories.
  -Enterprise              Include <Root>\enterprise\addons in addons_path.
  -NoStart                 Prepare the environment without starting Odoo.

Examples:
  .\odoo_install_windows.ps1 -Help
  .\odoo_install_windows.ps1 -InstallPrerequisites -NoStart
  .\odoo_install_windows.ps1 -Root D:\src\odoo-dev -SkipAddonRepos
'@ | Write-Host
}
function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found. Install prerequisites, then run this script again."
    }
}
function Invoke-Native([string]$File, [string[]]$Arguments) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $File $($Arguments -join ' ')" }
}
function Install-WingetPackage([string]$Id) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget is required for -InstallPrerequisites. Install App Installer or install the tools manually."
    }
    Invoke-Native 'winget' @('install', '--exact', '--id', $Id, '--accept-source-agreements', '--accept-package-agreements')
}
function Test-Python310 {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        & py -3.10 --version *> $null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $version = (& python --version 2>&1).ToString()
        if ($version -match '^Python 3\.10\.') { return $true }
    }
    return $false
}
function Install-MissingPackage([string]$Id, [scriptblock]$IsAvailable) {
    if (& $IsAvailable) {
        Write-Host "Already available: $Id" -ForegroundColor DarkGreen
    } else {
        Write-Host "Installing missing prerequisite: $Id"
        Install-WingetPackage $Id
    }
}
function Sync-Repository([string]$Path, [string]$Url, [string]$Branch) {
    if (Test-Path (Join-Path $Path '.git')) {
        Push-Location $Path
        try {
            Invoke-Native 'git' @('fetch', '--depth', '1', 'origin', $Branch)
            Invoke-Native 'git' @('checkout', $Branch)
            Invoke-Native 'git' @('pull', '--ff-only', 'origin', $Branch)
        } finally { Pop-Location }
    } elseif (Test-Path $Path) {
        throw "Target exists but is not a Git repository: $Path"
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
        Invoke-Native 'git' @('clone', '--depth', '1', '--branch', $Branch, $Url, $Path)
    }
}

Write-Host 'Odoo Windows development environment' -ForegroundColor Green
Write-Host "Root: $Root"

if ($Help) {
    Show-Help
    exit 0
}

if ($InstallPrerequisites) {
    Write-Step 'Installing prerequisites with winget'
    Install-MissingPackage 'Git.Git' { [bool](Get-Command git -ErrorAction SilentlyContinue) }
    Install-MissingPackage 'Python.Python.3.10' { Test-Python310 }
    Install-MissingPackage 'PostgreSQL.PostgreSQL.14' { [bool](Get-Command psql -ErrorAction SilentlyContinue) }
    Install-MissingPackage 'OpenJS.NodeJS.LTS' { [bool](Get-Command npm -ErrorAction SilentlyContinue) }
    if (-not (Get-Command git -ErrorAction SilentlyContinue) -or -not (Test-Python310) -or
        -not (Get-Command psql -ErrorAction SilentlyContinue) -or -not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Host 'Some packages were just installed. Restart PowerShell so PATH changes take effect, then run the script again.' -ForegroundColor Yellow
        exit 0
    }
}

Write-Step 'Checking prerequisites'
Assert-Command git
Assert-Command psql
Assert-Command npm
if (-not (Test-Python310)) { throw 'Python 3.10 was not found. Install it with -InstallPrerequisites.' }
$pythonCommand = 'python'
$pythonArguments = @()
if (Get-Command py -ErrorAction SilentlyContinue) {
    & py -3.10 --version *> $null
    if ($LASTEXITCODE -eq 0) { $pythonCommand = 'py'; $pythonArguments = @('-3.10') }
}
$pythonVersion = (& $pythonCommand @pythonArguments --version 2>&1).ToString()
Write-Host "Using $pythonVersion ($pythonCommand $($pythonArguments -join ' '))"

New-Item -ItemType Directory -Force -Path $Root | Out-Null
$odooPath = Join-Path $Root "odoo-$OdooVersion"
$venvPath = Join-Path $Root '.venv'
$configPath = Join-Path $Root 'odoo.conf'
$logPath = Join-Path $Root 'odoo.log'
$addons = @((Join-Path $odooPath 'addons'))

Write-Step 'Fetching Odoo source'
Sync-Repository $odooPath $OdooRepo $OdooBranch

if (-not $SkipAddonRepos) {
    Write-Step 'Fetching custom addons'
    $axantaPath = Join-Path $Root 'ax-addons-16'
    $whatsappPath = Join-Path $Root 'tu-whatsapp-v16'
    Sync-Repository $axantaPath $AxantaRepo $AxantaBranch
    Sync-Repository $whatsappPath $WhatsappRepo $WhatsappBranch
    $addons += $axantaPath
    foreach ($relative in @('oca_addons','3rd_party_addons','oca_reporting_addons','tier_validation','client_addons','oca_operating_unit')) {
        $candidate = Join-Path $axantaPath $relative
        if (Test-Path $candidate) { $addons += $candidate }
    }
    $addons += $whatsappPath
}

if ($Enterprise) {
    Write-Warning 'Enterprise source is not cloned automatically. Pass an authenticated enterprise checkout separately.'
    $enterpriseAddons = Join-Path $Root 'enterprise\addons'
    if (-not (Test-Path $enterpriseAddons)) { throw "Enterprise was requested but not found at $enterpriseAddons" }
    $addons = @($enterpriseAddons) + $addons
}

Write-Step 'Creating Python virtual environment'
if (-not (Test-Path (Join-Path $venvPath 'Scripts\python.exe'))) {
    Invoke-Native $pythonCommand ($pythonArguments + @('-m', 'venv', $venvPath))
}
$venvPython = Join-Path $venvPath 'Scripts\python.exe'
$venvPip = Join-Path $venvPath 'Scripts\pip.exe'
Invoke-Native $venvPython @('-m', 'pip', 'install', '--upgrade', 'pip', 'setuptools', 'wheel')
$requirements = Join-Path $odooPath 'requirements.txt'
if (Test-Path (Join-Path (Join-Path $Root 'ax-addons-16') 'requirements.txt')) {
    $requirements = Join-Path (Join-Path $Root 'ax-addons-16') 'requirements.txt'
}

Write-Step "Requirements file: $requirements"
Invoke-Native $venvPip @('install', '-r', $requirements)
Invoke-Native 'npm' @('install', '--global', 'rtlcss')

Write-Step 'Preparing PostgreSQL role'
$role = Split-Path $Root -Leaf
$role = ($role -replace '[^A-Za-z0-9_]', '_').ToLowerInvariant()
try {
    & psql -U postgres -d postgres -c "CREATE ROLE $role WITH LOGIN CREATEDB;" 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host "PostgreSQL role '$role' may already exist; continuing." -ForegroundColor Yellow }
} catch { Write-Warning 'Could not create the PostgreSQL role automatically. Create it in pgAdmin or psql if needed.' }

Write-Step 'Writing development configuration'
$addonValue = ($addons | ForEach-Object { $_ -replace '\\', '/' }) -join ','
$config = @(
    '[options]'
    "admin_passwd = admin"
    "db_host = localhost"
    'db_port = 5432'
    "db_user = $role"
    'db_password = False'
    "http_port = $OdooPort"
    "gevent_port = $LongpollingPort"
    "addons_path = $addonValue"
    "logfile = $($logPath -replace '\\', '/')"
    'workers = 0'
    'max_cron_threads = 1'
    'limit_time_cpu = 120'
    'limit_time_real = 240'
    'list_db = True'
    'proxy_mode = False'
)
Set-Content -Path $configPath -Value ($config -join [Environment]::NewLine) -Encoding UTF8

$runPath = Join-Path $Root 'run-odoo.ps1'
$run = @"
`$ErrorActionPreference = 'Stop'
& '$venvPython' '$odooPath\odoo-bin' '-c' '$configPath' '--dev=all'
"@
Set-Content -Path $runPath -Value $run -Encoding UTF8

Write-Host "`nSetup complete." -ForegroundColor Green
Write-Host "Config: $configPath"
Write-Host "Run:    powershell -ExecutionPolicy Bypass -File `"$runPath`""
Write-Host "URL:    http://localhost:$OdooPort"
if (-not $NoStart) {
    Write-Step 'Starting Odoo in the foreground'
    & $runPath
}
