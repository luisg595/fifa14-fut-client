param(
    [switch]$SkipVenvBootstrap,
    [switch]$ForceRepair
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-Python {
    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($name in @("py.exe", "py", "python.exe", "python")) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command -and $command.Source -and $command.Source -notlike "*\WindowsApps\*") {
            $candidates.Add([string]$command.Source)
        }
    }

    foreach ($base in @(
        (Join-Path $env:LOCALAPPDATA "Programs\Python"),
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    )) {
        if ([string]::IsNullOrWhiteSpace($base) -or -not (Test-Path -LiteralPath $base)) { continue }
        foreach ($pattern in @("Python313\python.exe", "Python312\python.exe", "Python311\python.exe", "Python310\python.exe", "Python3*\python.exe")) {
            $fullPattern = Join-Path $base $pattern
            Get-ChildItem -Path $fullPattern -File -ErrorAction SilentlyContinue | ForEach-Object { $candidates.Add($_.FullName) }
        }
    }

    $seen = @{}
    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        $key = $candidate.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        try {
            if ([IO.Path]::GetFileName($candidate) -in @("py.exe", "py")) {
                & $candidate -3 -c "import sys; assert sys.version_info >= (3,10); print(sys.executable)" *> $null
            } else {
                & $candidate -c "import sys; assert sys.version_info >= (3,10); print(sys.executable)" *> $null
            }
            if ($LASTEXITCODE -eq 0) { return $candidate }
        } catch {}
    }
    return $null
}

function Invoke-WinGetInstall {
    param([Parameter(Mandatory=$true)][string]$Id)
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { $winget = Get-Command winget -ErrorAction SilentlyContinue }
    if (-not $winget) { return $false }

    Write-Host ("Installing " + $Id + " with WinGet...") -ForegroundColor Cyan
    & $winget.Source install --id $Id -e --silent --accept-source-agreements --accept-package-agreements --disable-interactivity
    if ($LASTEXITCODE -eq 0) { return $true }
    Write-Host ("WinGet could not install " + $Id + " (exit " + $LASTEXITCODE + "). Trying the official direct-download fallback.") -ForegroundColor Yellow
    return $false
}

function Install-PythonFallback {
    # Pinned, known-good CPython used by this build. Keep the SHA-256 check so
    # a partial or replaced download is never executed.
    $version = "3.13.15"
    $url = "https://www.python.org/ftp/python/$version/python-$version-amd64.exe"
    $expectedSha256 = "EDEC09C4853AEAE9AC36EFB8C9F95B6B8E2FEE65EEE56D9767A8B7C69C574403"
    $download = Join-Path $env:TEMP ("python-" + $version + "-amd64.exe")

    Write-Host ("Downloading CPython " + $version + " from python.org...") -ForegroundColor Cyan
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $download
    $actual = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $expectedSha256) {
        Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue
        throw "Python installer SHA-256 mismatch. Refusing to execute the download."
    }

    Write-Host "Installing CPython 3.13 for all users..." -ForegroundColor Cyan
    $proc = Start-Process -FilePath $download -ArgumentList @(
        "/quiet", "InstallAllUsers=1", "PrependPath=1", "Include_launcher=1", "Include_test=0"
    ) -Wait -PassThru
    Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue
    if ($proc.ExitCode -ne 0) { throw "Python installer failed with exit code $($proc.ExitCode)." }
}

if (-not (Test-IsAdministrator)) {
    Write-Host "Administrator rights are required for the prerequisite installer. Requesting elevation..." -ForegroundColor Yellow
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ('"' + $PSCommandPath + '"'))
    if ($SkipVenvBootstrap) { $argList += "-SkipVenvBootstrap" }
    if ($ForceRepair) { $argList += "-ForceRepair" }
    $p = Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argList -Wait -PassThru
    exit $p.ExitCode
}

Write-Host "============================================================"
Write-Host " FIFA 14 FUT CLIENT - PREREQUISITES"
Write-Host "============================================================"
Write-Host "Checks/installs: Python 3.10+, then the project Python environment."
Write-Host ""

$python = Find-Python
if ($ForceRepair -or -not $python) {
    if (-not $python) { Write-Host "Python 3.10+ was not found." -ForegroundColor Yellow }
    if (-not (Invoke-WinGetInstall -Id "Python.Python.3.13")) {
        Install-PythonFallback
    }
    $python = Find-Python
}
if (-not $python) { throw "Python installation finished but no working Python 3.10+ interpreter could be found." }
Write-Host ("[OK] Python: " + $python) -ForegroundColor Green

if (-not $SkipVenvBootstrap) {
    Write-Host "Creating/repairing the project Python environment and pip dependencies..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "bootstrap.ps1")
    if ($LASTEXITCODE -ne 0) { throw "Python dependency bootstrap failed." }
}

Write-Host ""
Write-Host "PREREQUISITES READY." -ForegroundColor Green
Write-Host "You can now run INSTALL_GAME_PATCHES.cmd / RUN_REMOTE_FUT.cmd." -ForegroundColor Green
exit 0
