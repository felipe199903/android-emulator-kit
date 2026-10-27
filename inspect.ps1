# Diagnostic shortcuts. Usage: .\inspect.ps1 <logs|crash|ui|record|webview> [-Package com.example.app]
param(
    [Parameter(Mandatory)][ValidateSet('logs', 'crash', 'ui', 'record', 'webview')][string]$Command,
    [string]$Package
)
. "$PSScriptRoot\config.ps1"

if (-not (Test-EmulatorBooted)) { throw "Emulator $Serial is not running. Run .\start.ps1 first." }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Assert-Package {
    if (-not $Package) { throw 'Pass -Package (e.g. -Package com.example.app). To list installed apps: adb shell pm list packages -3' }
}

function Get-AppPid {
    Assert-Package
    $appPid = (Invoke-Native { Invoke-Adb shell pidof $Package }).Trim()
    if (-not $appPid) { throw "$Package is not running. Open the app in the emulator and try again." }
    $appPid
}

# The UID is stable across app restarts, unlike the PID.
function Get-AppUid {
    Assert-Package
    $list = Invoke-Native { Invoke-Adb shell pm list packages -U $Package }
    if ($list -notmatch "(?m)^package:$([regex]::Escape($Package)) uid:(\d+)") { throw "$Package is not installed. To list: adb shell pm list packages -3" }
    $Matches[1]
}

switch ($Command) {
    'logs' {
        $uid = Get-AppUid
        $file = Join-Path $OutDir "logs-$stamp.txt"
        Write-Host "Recording to $file (Ctrl+C to stop; keeps going if the app restarts)"
        Invoke-Adb logcat -v time --uid=$uid | Tee-Object -FilePath $file
    }
    'crash' {
        $file = Join-Path $OutDir "crash-$stamp.txt"
        # dropbox keeps recent crashes and ANRs with the full stack trace
        & { Invoke-Adb logcat -d -v time -b crash; '--- dropbox (crash/ANR) ---'; Invoke-Adb shell dumpsys dropbox --print data_app_crash data_app_anr } | Tee-Object -FilePath $file
    }
    'ui' {
        Invoke-Native {
            Invoke-Adb shell uiautomator dump /sdcard/ui.xml
            Invoke-Adb pull /sdcard/ui.xml (Join-Path $OutDir "ui-$stamp.xml")
            Invoke-Adb shell screencap -p /sdcard/screen.png
            Invoke-Adb pull /sdcard/screen.png (Join-Path $OutDir "ui-$stamp.png")
        } | Out-Null
        Write-Host "Saved: out\ui-$stamp.xml and out\ui-$stamp.png"
    }
    'record' {
        Write-Host 'Recording the screen (max 3 min). Press Enter to stop.'
        $rec = Start-Process $AdbExe -ArgumentList '-s', $Serial, 'shell', 'screenrecord', '/sdcard/rec.mp4' -PassThru -NoNewWindow
        Read-Host | Out-Null
        Invoke-Adb shell pkill -INT screenrecord
        $rec.WaitForExit()
        Start-Sleep 1
        Invoke-Native { Invoke-Adb pull /sdcard/rec.mp4 (Join-Path $OutDir "rec-$stamp.mp4") } | Out-Null
        Write-Host "Saved: out\rec-$stamp.mp4"
    }
    'webview' {
        # Unix socket names: @chrome_devtools_remote (Chrome), @webview_devtools_remote_<pid> (app WebViews)
        $sockets = @(Invoke-Adb shell cat /proc/net/unix | Select-String 'devtools_remote' | ForEach-Object { ($_ -split '\s+')[-1].TrimStart('@') } | Sort-Object -Unique)
        if ($Package) {
            $appPid = Get-AppPid
            $sockets = @($sockets | Where-Object { $_ -like "*_$appPid" -or $_ -like "$Package*" })
        }
        if (-not $sockets) {
            Write-Warning 'No active WebView/DevTools target. Open the screen with the WebView in the app (pure React Native/Flutter apps have none; use "ui").'
            return
        }
        Write-Host "DevTools targets: $($sockets -join ', ')"
        Open-Inspector
    }
}
