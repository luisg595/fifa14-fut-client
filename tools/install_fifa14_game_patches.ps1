$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "common.ps1")

$projectRoot = Get-ProjectRoot
$python = Resolve-ProjectPython

$paths = Resolve-Fifa14Paths -PromptIfMissing -PersistDetected
$GameRoot = $paths.GameRoot

Write-Host "FIFA 14 game root: $GameRoot" -ForegroundColor Cyan

Stop-Fifa14ForOnDiskPatch

Write-Host "== 1/6 Spinner branch bypass =="
& (Join-Path $PSScriptRoot "apply_fifa14_fut_branch_bypass.ps1") -Mode branch-offline -GameRoot $GameRoot -AllowUnknown
if ($LASTEXITCODE -ne 0) { throw "branch bypass failed" }

Write-Host "== 2/6 FCC login1 popup =="
& (Join-Path $PSScriptRoot "apply_fifa14_fcc_login1_popup.ps1") -GameRoot $GameRoot
if ($LASTEXITCODE -ne 0) { throw "FCC login1 popup failed" }

Write-Host "== 3/6 Intro VP6 =="
& (Join-Path $PSScriptRoot "apply_fifa14_fut_intro_vp6_v19.ps1") -GameRoot $GameRoot
if ($LASTEXITCODE -ne 0) { throw "Intro VP6 failed" }

Write-Host "== 4/6 PackSelect retail restore =="
& (Join-Path $PSScriptRoot "restore_fifa14_fut_packselect_retail_v19.ps1") -GameRoot $GameRoot -AllowUnknown
if ($LASTEXITCODE -ne 0) { throw "PackSelect restore failed" }

Write-Host "== 5/6 Legends safeguard (--restore) =="
$legendsReport = Join-Path $projectRoot "artifacts\fifa14-legends-scan.json"
& $python (Join-Path $PSScriptRoot "patch_fifa14_fut_legends_db.py") --game-root $GameRoot --output-report $legendsReport --restore
if ($LASTEXITCODE -ne 0) { throw "legends safeguard failed" }

Write-Host "== 6/6 Match-assets scan =="
$matchAssets = Join-Path $projectRoot "artifacts\fifa14-match-assets-v2411-beta222.json"
& $python (Join-Path $PSScriptRoot "scan_fifa14_match_assets.py") --game-root $GameRoot --output $matchAssets
if ($LASTEXITCODE -ne 0) { throw "match-assets scan failed" }

$serverSettings = Get-ServerSettings
$serverReady = $false
if (-not [string]::IsNullOrWhiteSpace($serverSettings.ServerHost)) {
    try {
        $health = Invoke-RestMethod -Uri "http://$($serverSettings.ServerHost):$($serverSettings.ServerHttpPort)/__fifa14_local_fut_health" -TimeoutSec 4
        $serverReady = $true
    } catch {
        $serverReady = $false
    }
}

if ($serverReady) {
    Write-Host "Uploading match-assets report to the server..."
    $jsonBody = [IO.File]::ReadAllText($matchAssets)
    $uploadResult = Invoke-RestMethod -Uri "http://$($serverSettings.ServerHost):$($serverSettings.ServerHttpPort)/__fifa14_local_fut_upload_match_assets" `
        -Method Post `
        -Headers @{ "X-Admin-Secret" = $serverSettings.AdminSecret } `
        -ContentType "application/json" `
        -Body $jsonBody -TimeoutSec 10
    Write-Host ("Upload OK: saved=" + $uploadResult.saved + " bytes=" + $uploadResult.bytes) -ForegroundColor Green

    $caDir = Join-Path $projectRoot "artifacts\local-old-protossl"
    $caFile = Join-Path $caDir "old-protossl-otg3-ca.pem"
    if (-not (Test-Path -LiteralPath $caFile -PathType Leaf)) {
        New-Item -ItemType Directory -Path $caDir -Force | Out-Null
        Invoke-WebRequest -Uri "http://$($serverSettings.ServerHost):$($serverSettings.ServerHttpPort)/__fifa14_local_fut_ca" -OutFile $caFile -UseBasicParsing
        Write-Host "Downloaded CA certificate to $caFile"
    }
} else {
    Write-Warning "Server not reachable. Match-assets upload and CA download skipped; re-run INSTALL_GAME_PATCHES.cmd once ./up.sh is done."
}

if (-not (Test-Path -LiteralPath (Join-Path $projectRoot "config.local.psd1"))) {
    Write-Host ""
    Write-Host "config.local.psd1 not found. Creating it..."
    if ([string]::IsNullOrWhiteSpace($serverSettings.ServerHost)) {
        $serverHost = Read-Host "FUT server IP (ServerHost, e.g. 192.168.1.50)"
    } else {
        $serverHost = $serverSettings.ServerHost
    }
    $serverHttpPort = if ([string]::IsNullOrWhiteSpace($serverSettings.ServerHttpPort)) { "8099" } else { $serverSettings.ServerHttpPort }
    $adminSecret = $serverSettings.AdminSecret
    if ([string]::IsNullOrWhiteSpace($adminSecret)) {
        $adminSecret = Read-Host "Admin secret (AdminSecret, shared with the server .env)"
    }
    Save-Fifa14Config -GameRoot $GameRoot -ServerHost $serverHost -ServerHttpPort $serverHttpPort -AdminSecret $adminSecret
    Write-Host "Saved config.local.psd1"
}

$ports = @(42129, 42128, 8081, 8099, 8306, 44125)
Write-Host ""
Write-Host "== Server port reachability (from this Windows host) =="
foreach ($port in $ports) {
    $ok = Test-NetConnection -ComputerName $serverSettings.ServerHost -Port $port -WarningAction SilentlyContinue
    $status = if ($ok.TcpTestSucceeded) { "OK" } else { "FAIL" }
    Write-Host ("  {0}: {1}" -f $port, $status)
}

Write-Host ""
Write-Host "Install complete. You can now run RUN_REMOTE_FUT.cmd." -ForegroundColor Green
