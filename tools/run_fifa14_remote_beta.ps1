param(
    [switch]$Diagnose
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

$projectRoot = Get-ProjectRoot
$python = Resolve-ProjectPython

$paths = Resolve-Fifa14Paths -PromptIfMissing -PersistDetected
$GameRoot = $paths.GameRoot
$GameExe = $paths.GameExe

$serverSettings = Get-ServerSettings
if ([string]::IsNullOrWhiteSpace($serverSettings.ServerHost)) {
    throw "ServerHost is not configured. Set it in config.local.psd1 or FIFA14_SERVER_HOST env."
}
$ServerHost = $serverSettings.ServerHost
$ServerHttpPort = $serverSettings.ServerHttpPort

$accountKey = ""
while ($true) {
    $prompt = Read-Host "Username (required; [A-Za-z0-9_-]{1,63})"
    $prompt = ($prompt | ForEach-Object { $_.Trim() })
    if ([string]::IsNullOrWhiteSpace($prompt)) {
        Write-Host "A username is required. Each person must enter their own." -ForegroundColor Yellow
        continue
    }
    if ($prompt -match '^[A-Za-z0-9_-]{1,63}$') {
        $accountKey = $prompt
        break
    }
    Write-Host "Invalid username. Use only A-Z a-z 0-9 _ - (1-63 chars)." -ForegroundColor Yellow
}
Write-Host "Account: $accountKey" -ForegroundColor Cyan

# Persist the account chosen for this session so GIVE_100M_TEST_COINS.cmd can
# target the same persona without asking (see give_coins_remote.ps1).
$currentAccountFile = Join-Path $projectRoot "artifacts\fut-current-account.txt"
New-Item -ItemType Directory -Path (Split-Path -Parent $currentAccountFile) -Force | Out-Null
[IO.File]::WriteAllText($currentAccountFile, $accountKey, [Text.Encoding]::ASCII)

Write-Host "Server: http://${ServerHost}:${ServerHttpPort}" -ForegroundColor Cyan

Stop-Fifa14ForOnDiskPatch
Stop-ProjectHelpers

$healthUri = "http://${ServerHost}:${ServerHttpPort}/__fifa14_local_fut_health"
Write-Host "Waiting for the remote FUT server..."
$health = $null
$deadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $deadline) {
    try {
        $health = Invoke-RestMethod -Uri $healthUri -TimeoutSec 3
        break
    } catch {
        Start-Sleep -Seconds 1
    }
}
if ($null -eq $health) {
    throw "FUT server did not become reachable at $healthUri. Run ./up.sh on the server first."
}
if ($health.buildVersion -ne "2.41.1-beta2.25.9") {
    throw "Unexpected FUT server buildVersion: $($health.buildVersion). Expected 2.41.1-beta2.25.9."
}
$flatKeys = @("itemType", "cardsubtypeid", "nation", "leagueId", "resourceGameYear")
foreach ($key in $flatKeys) {
    if (-not ($health.samplePlayer.PSObject.Properties.Name -contains $key)) {
        throw "samplePlayer is missing flat ItemData key: $key"
    }
}
if (-not $health.hasClub) {
    throw "FUT server reports hasClub=false; prepare_state.py should have seeded the starter club."
}
Write-Host ("Server health OK (build " + $health.buildVersion + ", hasClub " + $health.hasClub + ", profileKind " + $health.profileKind + ")") -ForegroundColor Green

$routeStateDir = Join-Path $projectRoot "artifacts\fut-nav-route-v19"
Write-Host "Restoring retail NAV route..."
& $python (Join-Path $PSScriptRoot "patch_fifa14_fut_dynamic_route.py") --game-root $GameRoot --state-dir $routeStateDir --restore-retail --allow-unknown
if ($LASTEXITCODE -ne 0) { throw "patch_fifa14_fut_dynamic_route.py --restore-retail failed" }

$caDir = Join-Path $projectRoot "artifacts\local-old-protossl"
$caFile = Join-Path $caDir "old-protossl-otg3-ca.pem"
if (-not (Test-Path -LiteralPath $caFile -PathType Leaf)) {
    Write-Host "Downloading CA certificate from the server..."
    New-Item -ItemType Directory -Path $caDir -Force | Out-Null
    Invoke-WebRequest -Uri "http://${ServerHost}:${ServerHttpPort}/__fifa14_local_fut_ca" -OutFile $caFile -UseBasicParsing
}

$clIni = Join-Path $GameRoot "cl.ini"
$clIniBackup = Join-Path $GameRoot "cl.ini.fut-remote.bak"
if (Test-Path -LiteralPath $clIni -PathType Leaf) {
    Copy-Item -LiteralPath $clIni -Destination $clIniBackup -Force
    Write-Host "Backed up cl.ini to $clIniBackup"
}
[IO.File]::WriteAllText($clIni, "FUT_ENABLE_MENU = 1`r`n", [Text.Encoding]::ASCII)

$helperLog = Join-Path $projectRoot "artifacts\frida.log"
$helperOut = Join-Path $projectRoot "artifacts\frida.out.log"
$helperErr = Join-Path $projectRoot "artifacts\frida.err.log"
$helperPath = Join-Path $PSScriptRoot "frida_pc_fut_nav_route_patch_trace.py"

try {
    Write-Host "Launching $GameExe ..."
    $launcher = [System.Diagnostics.Process]::Start((New-Object System.Diagnostics.ProcessStartInfo -Property @{
        FileName = $GameExe
        WorkingDirectory = $GameRoot
    }))
    $launcherPid = $launcher.Id
    Write-Host "Launcher PID $launcherPid; waiting for the real fifa14.exe..."

    $fifaProcess = Wait-Fifa14GameplayProcess -LauncherPid $launcherPid -Seconds 300
    $fifaPid = [int]$fifaProcess.Id
    Write-Host "Selected gameplay fifa14.exe as PID $fifaPid" -ForegroundColor Green

    Write-Host "Waiting 15s for language selection / main menu before attaching..."
    Start-Sleep -Seconds 15

    $helperArgs = @(
        (Quote-Arg $helperPath),
        "--pid", "$fifaPid",
        "--ca-file", (Quote-Arg $caFile),
        "--server-ip", (Quote-Arg $ServerHost),
        "--log", (Quote-Arg $helperLog),
        "--run-seconds", "1800"
    ) -join " "
    if ($accountKey) {
        $helperArgs = $helperArgs + " " + "--account" + " " + (Quote-Arg $accountKey)
    }
    if ($Diagnose) {
        $helperArgs = $helperArgs + " " + "--diagnose"
        Write-Host "Diagnostic telemetry enabled (--diagnose)" -ForegroundColor Yellow
    }

    $helper = Start-Process -FilePath $python -ArgumentList $helperArgs `
        -RedirectStandardOutput $helperOut -RedirectStandardError $helperErr `
        -PassThru -WindowStyle Hidden

    $deadline = (Get-Date).AddSeconds(30)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $helperLog) {
            if (Select-String -LiteralPath $helperLog -Pattern 'native-fut-nav-route-patch-trace-ready' -Quiet) { $ready = $true; break }
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw "Frida helper did not report ready. See $helperErr" }
    if (Select-String -LiteralPath $helperLog -Pattern '"hooks_enabled": false' -Quiet) {
        throw "The decrypted FIFA runtime signatures did not match this exact build. Native hooks were not armed. See $helperLog"
    }

    Write-Host ""
    Write-Host "READY. Enter FUT; the retail NAV route is armed." -ForegroundColor Green
    Write-Host "Press Enter to detach and exit..." -ForegroundColor Yellow
    [Console]::ReadLine() | Out-Null
} finally {
    if (Test-Path -LiteralPath $clIniBackup -PathType Leaf) {
        Copy-Item -LiteralPath $clIniBackup -Destination $clIni -Force
    } else {
        Remove-Item -LiteralPath $clIni -Force -ErrorAction SilentlyContinue
    }
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.CommandLine -like "*frida_pc_fut_nav_route_patch_trace.py*") {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
}
