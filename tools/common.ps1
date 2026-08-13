Set-StrictMode -Version Latest

function Get-ProjectRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Get-LocalConfig {
    $projectRoot = Get-ProjectRoot
    $configPath = Join-Path $projectRoot "config.local.psd1"
    if (Test-Path -LiteralPath $configPath) {
        return Import-PowerShellDataFile -LiteralPath $configPath
    }
    return @{}
}

function Save-Fifa14Config {
    param(
        [Parameter(Mandatory=$true)][string]$GameRoot,
        [string]$ServerHost,
        [string]$ServerHttpPort,
        [string]$AdminSecret
    )
    $projectRoot = Get-ProjectRoot
    $GameRoot = [IO.Path]::GetFullPath($GameRoot.Trim().Trim('"'))
    $GameExe = Join-Path $GameRoot "fifa14.exe"
    $escape = { param([string]$Value) $Value.Replace("'", "''") }
    $configPath = Join-Path $projectRoot "config.local.psd1"
    $rootEscaped = & $escape $GameRoot
    $exeEscaped = & $escape $GameExe
    $content = "@{`r`n    GameRoot = '$rootEscaped'`r`n    GameExe  = '$exeEscaped'`r`n"
    if (-not [string]::IsNullOrWhiteSpace($ServerHost)) {
        $content += "    ServerHost = '$(& $escape $ServerHost)'`r`n"
    }
    if (-not [string]::IsNullOrWhiteSpace($ServerHttpPort)) {
        $content += "    ServerHttpPort = '$(& $escape $ServerHttpPort)'`r`n"
    }
    if (-not [string]::IsNullOrWhiteSpace($AdminSecret)) {
        $content += "    AdminSecret = '$(& $escape $AdminSecret)'`r`n"
    }
    $content += "}`r`n"
    Set-Content -LiteralPath $configPath -Value $content -Encoding UTF8
    return $configPath
}

function Get-ServerSettings {
    $config = Get-LocalConfig
    $serverHost = if ($config.ContainsKey("ServerHost")) { [string]$config.ServerHost } else { "" }
    if ([string]::IsNullOrWhiteSpace($serverHost)) { $serverHost = $env:FIFA14_SERVER_HOST }

    $serverHttpPort = if ($config.ContainsKey("ServerHttpPort")) { [string]$config.ServerHttpPort } else { "" }
    if ([string]::IsNullOrWhiteSpace($serverHttpPort)) { $serverHttpPort = $env:FIFA14_SERVER_HTTP_PORT }
    if ([string]::IsNullOrWhiteSpace($serverHttpPort)) { $serverHttpPort = "8099" }

    $adminSecret = if ($config.ContainsKey("AdminSecret")) { [string]$config.AdminSecret } else { "" }
    if ([string]::IsNullOrWhiteSpace($adminSecret)) { $adminSecret = $env:FIFA14_ADMIN_SECRET }

    return [pscustomobject]@{
        ServerHost = $serverHost.Trim().Trim('"')
        ServerHttpPort = $serverHttpPort.Trim().Trim('"')
        AdminSecret = $adminSecret.Trim().Trim('"')
    }
}

function Get-Fifa14AutoDetectCandidates {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($fixed in @(
        "C:\Program Files\EA Games\FIFA 14\Game",
        "C:\Program Files (x86)\Origin Games\FIFA 14\Game",
        "C:\Program Files\Origin Games\FIFA 14\Game"
    )) { $candidates.Add($fixed) }

    foreach ($drive in [IO.DriveInfo]::GetDrives()) {
        if (-not $drive.IsReady) { continue }
        $root = $drive.RootDirectory.FullName
        foreach ($relative in @(
            "EA Games\FIFA 14\Game",
            "Games\FIFA 14\Game",
            "Origin Games\FIFA 14\Game",
            "SteamLibrary\steamapps\common\FIFA 14\Game",
            "Program Files\EA Games\FIFA 14\Game",
            "Program Files (x86)\Origin Games\FIFA 14\Game"
        )) { $candidates.Add((Join-Path $root $relative)) }
    }
    return @($candidates | Select-Object -Unique)
}

function Resolve-Fifa14Paths {
    param(
        [string]$GameRoot,
        [string]$GameExe,
        [bool]$RequireExe = $true,
        [switch]$PromptIfMissing,
        [switch]$PersistDetected
    )

    $config = Get-LocalConfig
    $source = "command line"

    if ([string]::IsNullOrWhiteSpace($GameRoot) -and -not [string]::IsNullOrWhiteSpace($GameExe)) {
        $GameRoot = Split-Path -Parent $GameExe
    }
    if ([string]::IsNullOrWhiteSpace($GameRoot) -and $config.ContainsKey("GameRoot")) {
        $GameRoot = [string]$config.GameRoot
        $source = "config.local.psd1"
    }
    if ([string]::IsNullOrWhiteSpace($GameExe) -and $config.ContainsKey("GameExe")) {
        $GameExe = [string]$config.GameExe
    }
    if ([string]::IsNullOrWhiteSpace($GameRoot) -and -not [string]::IsNullOrWhiteSpace($env:FIFA14_GAME_ROOT)) {
        $GameRoot = $env:FIFA14_GAME_ROOT
        $source = "FIFA14_GAME_ROOT"
    }

    if ([string]::IsNullOrWhiteSpace($GameRoot)) {
        foreach ($candidate in Get-Fifa14AutoDetectCandidates) {
            if (Test-Path -LiteralPath (Join-Path $candidate "fifa14.exe") -PathType Leaf) {
                $GameRoot = $candidate
                $source = "auto-detected"
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($GameRoot) -and $PromptIfMissing) {
        Write-Host "FIFA 14 was not found automatically." -ForegroundColor Yellow
        Write-Host "Paste your FIFA 14 Game folder (the folder containing fifa14.exe)."
        $GameRoot = Read-Host "FIFA 14 Game folder"
        $source = "interactive setup"
    }

    if ([string]::IsNullOrWhiteSpace($GameRoot)) {
        throw "FIFA 14 Game folder was not found. Run INSTALL_GAME_PATCHES.cmd once, create config.local.psd1 from config.local.psd1.example, or set FIFA14_GAME_ROOT."
    }

    $GameRoot = [IO.Path]::GetFullPath($GameRoot.Trim().Trim('"'))
    if ([string]::IsNullOrWhiteSpace($GameExe)) { $GameExe = Join-Path $GameRoot "fifa14.exe" }
    $GameExe = [IO.Path]::GetFullPath($GameExe.Trim().Trim('"'))

    if (-not (Test-Path -LiteralPath $GameRoot -PathType Container)) {
        throw "FIFA 14 Game folder does not exist: $GameRoot"
    }
    if ($RequireExe -and -not (Test-Path -LiteralPath $GameExe -PathType Leaf)) {
        throw "fifa14.exe was not found at: $GameExe"
    }

    if ($PersistDetected -and $source -in @("auto-detected", "interactive setup", "FIFA14_GAME_ROOT")) {
        $saved = Save-Fifa14Config -GameRoot $GameRoot
        Write-Host ("Saved FIFA 14 path for future launches: " + $saved) -ForegroundColor DarkGray
    }

    return [pscustomobject]@{ GameRoot=$GameRoot; GameExe=$GameExe; Source=$source }
}

function Resolve-ProjectPython {
    $projectRoot = Get-ProjectRoot
    $venvPython = Join-Path $projectRoot ".venv\Scripts\python.exe"
    if (Test-Path -LiteralPath $venvPython -PathType Leaf) {
        return $venvPython
    }

    throw "Project Python environment is missing. Run .\tools\bootstrap.ps1 first."
}

function Stop-ProjectHelpers {
    # Remote client helpers only: the Frida NAV trace. The server-side probe
    # and watchers live on the remote host and must not be touched here.
    $helperPatterns = @(
        "frida_pc_fut_nav_route_patch_trace.py"
    )

    $stopped = @()
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
        $command = [string]$_.CommandLine
        if ([string]::IsNullOrWhiteSpace($command)) { return }

        $matchesHelper = $false
        foreach ($pattern in $helperPatterns) {
            if ($command -like "*$pattern*") { $matchesHelper = $true; break }
        }
        if (-not $matchesHelper) { return }

        try {
            $stopped += [pscustomobject]@{
                Pid = [int]$_.ProcessId
                Name = [string]$_.Name
                CommandLine = $command
            }
            Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
        } catch {
            Write-Warning ("Could not stop stale FIFA-local helper PID {0}: {1}" -f $_.ProcessId, $_.Exception.Message)
        }
    }

    foreach ($entry in $stopped) {
        Write-Host ("Stopped stale FIFA-local helper PID {0}: {1}" -f $entry.Pid, $entry.Name)
    }
    if ($stopped.Count -gt 0) {
        Start-Sleep -Milliseconds 750
    }
}

function Stop-Fifa14ForOnDiskPatch {
    $running = @(Get-Process -Name "fifa14" -ErrorAction SilentlyContinue)
    if ($running.Count -eq 0) { return }

    Write-Host ("Closing stale FIFA 14 process(es) before on-disk patching: " + (($running | ForEach-Object { $_.Id }) -join ", ")) -ForegroundColor Yellow
    $running | Stop-Process -Force -ErrorAction Stop
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $running = @(Get-Process -Name "fifa14" -ErrorAction SilentlyContinue)
    } while ($running.Count -gt 0 -and (Get-Date) -lt $deadline)

    if ($running.Count -gt 0) {
        throw "Could not close fifa14.exe before on-disk FUT patching."
    }
}

function Get-Fifa14ProcessCandidates {
    $items = @()
    foreach ($process in @(Get-Process -Name "fifa14" -ErrorAction SilentlyContinue)) {
        try { $process.Refresh() } catch { continue }
        if ($process.HasExited) { continue }

        $started = $null
        try { $started = $process.StartTime } catch { $started = Get-Date }
        $path = ""
        try { $path = [string]$process.Path } catch { $path = "<unavailable>" }
        $windowHandle = 0
        $windowTitle = ""
        try {
            $windowHandle = [int64]$process.MainWindowHandle
            $windowTitle = [string]$process.MainWindowTitle
        } catch { }

        $items += [pscustomobject]@{
            Process = $process
            Id = [int]$process.Id
            StartTime = $started
            Path = $path
            MainWindowHandle = $windowHandle
            MainWindowTitle = $windowTitle
        }
    }
    return @($items)
}

function Wait-Fifa14GameplayProcess {
    param(
        [int]$LauncherPid,
        [int[]]$RejectedPids = @(),
        [int]$Seconds = 300
    )

    $firstSeen = @{}
    $lastSnapshot = ""
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $candidates = @(Get-Fifa14ProcessCandidates | Where-Object { $RejectedPids -notcontains $_.Id })
        $snapshot = ($candidates | ForEach-Object {
            "pid={0},window=0x{1:X},title={2},path={3}" -f $_.Id, $_.MainWindowHandle, $_.MainWindowTitle, $_.Path
        }) -join " | "
        if ($snapshot -ne $lastSnapshot) {
            if ($snapshot) { Write-ProcessHandoffLog "candidates: $snapshot" }
            else { Write-ProcessHandoffLog "candidates: none" }
            $lastSnapshot = $snapshot
        }

        foreach ($candidate in $candidates) {
            $key = [string]$candidate.Id
            if (-not $firstSeen.ContainsKey($key)) {
                $firstSeen[$key] = Get-Date
            }
        }

        $eligible = @()
        foreach ($candidate in $candidates) {
            if ($candidate.MainWindowHandle -eq 0) { continue }
            $key = [string]$candidate.Id
            $stableSeconds = ((Get-Date) - [datetime]$firstSeen[$key]).TotalSeconds
            # The process returned by Process.Start can be an EA handoff stub. Give a
            # replacement fifa14.exe time to appear before accepting the original PID.
            $requiredStableSeconds = if ($candidate.Id -eq $LauncherPid) { 12 } else { 3 }
            if ($stableSeconds -ge $requiredStableSeconds) {
                $eligible += $candidate
            }
        }

        if ($eligible.Count -gt 0) {
            $selected = $eligible |
                Sort-Object @{ Expression = { if ($_.Id -eq $LauncherPid) { 1 } else { 0 } } }, `
                            @{ Expression = { $_.StartTime }; Descending = $true } |
                Select-Object -First 1
            Write-ProcessHandoffLog ("selected gameplay process pid={0}, launcher_pid={1}, window=0x{2:X}, title={3}, path={4}" -f `
                $selected.Id, $LauncherPid, $selected.MainWindowHandle, $selected.MainWindowTitle, $selected.Path)
            return $selected.Process
        }

        Start-Sleep -Milliseconds 250
    }

    $rejected = if ($RejectedPids.Count -gt 0) { $RejectedPids -join "," } else { "none" }
    throw "Timed out waiting for the real FIFA 14 gameplay process (launcher PID $LauncherPid; rejected PIDs $rejected)."
}

function Write-ProcessHandoffLog {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffK"), $Message
    Add-Content -LiteralPath $script:processLog -Value $line -Encoding UTF8
}

function Quote-Arg([string]$Value) {
    return '"' + ($Value -replace '"', '\"') + '"'
}

$script:processLog = Join-Path (Get-ProjectRoot) "artifacts\process-handoff.log"
