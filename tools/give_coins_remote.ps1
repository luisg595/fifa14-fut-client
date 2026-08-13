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
$body = '{"coins": 100000000}'
Write-Host ("POST " + $uri)

try {
    $result = Invoke-RestMethod -Uri $uri -Method Post `
        -Headers @{ "X-Admin-Secret" = $serverSettings.AdminSecret } `
        -ContentType "application/json" -Body $body -TimeoutSec 10
    Write-Host ("granted=" + $result.granted + " balance=" + $result.balance) -ForegroundColor Green
} catch {
    Write-Host ("give_coins failed: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host "If the server rejects admin calls, run ./admin/give_coins.sh on the server host." -ForegroundColor Yellow
}
