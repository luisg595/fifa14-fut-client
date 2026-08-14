$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "common.ps1")

$serverSettings = Get-ServerSettings
if ([string]::IsNullOrWhiteSpace($serverSettings.ServerHost)) {
    throw "ServerHost is not configured. Set it in config.local.psd1 or FIFA14_SERVER_HOST env."
}
if ([string]::IsNullOrWhiteSpace($serverSettings.AdminSecret)) {
    throw "AdminSecret is not configured. Set it in config.local.psd1 or FIFA14_ADMIN_SECRET env."
}

$uri = "http://$($serverSettings.ServerHost):$($serverSettings.ServerHttpPort)/__fifa14_local_fut_admin/give_coins"

# Target the account of the current FUT session on this machine (written by
# run_fifa14_remote_beta.ps1). Empty or missing => the server default persona.
$currentAccountFile = Join-Path (Get-ProjectRoot) "artifacts\fut-current-account.txt"
$accountKey = ""
if (Test-Path -LiteralPath $currentAccountFile -PathType Leaf) {
    $accountKey = [IO.File]::ReadAllText($currentAccountFile).Trim()
}

$body = @{ coins = 100000000 }
if ($accountKey) { $body["account"] = $accountKey }
$json = $body | ConvertTo-Json -Compress
Write-Host ("POST " + $uri)
if ($accountKey) { Write-Host ("Account: " + $accountKey) -ForegroundColor Cyan }
else { Write-Host "Account: (default)" -ForegroundColor Cyan }

try {
    $result = Invoke-RestMethod -Uri $uri -Method Post `
        -Headers @{ "X-Admin-Secret" = $serverSettings.AdminSecret } `
        -ContentType "application/json" -Body $json -TimeoutSec 10
    Write-Host ("granted=" + $result.granted + " balance=" + $result.balance) -ForegroundColor Green
} catch {
    Write-Host ("give_coins failed: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host "If the server rejects admin calls, run ./admin/give_coins.sh on the server host." -ForegroundColor Yellow
}
