# Opens a URL in the emulator's Chrome and the DevTools inspector on the PC. Boots the emulator if needed.
# Usage: .\open.ps1 localhost:3000   |   .\open.ps1 https://example.com
param(
    [Parameter(Mandatory, Position = 0)][string]$Url,
    [switch]$NoInspector    # don't open chrome://inspect on the PC
)
. "$PSScriptRoot\config.ps1"

& "$PSScriptRoot\start.ps1"

if ($Url -notmatch '^[a-z][a-z0-9+.-]*://') { $Url = "http://$Url" }
$uri = [Uri]$Url

# localhost on the phone is the phone itself: tunnel the port back to the PC with `adb reverse`.
# This keeps the origin as localhost (secure context: service workers, geolocation, etc. keep working).
if ($uri.Host -in 'localhost', '127.0.0.1', '[::1]') {
    $out = Invoke-Native { Invoke-Adb reverse "tcp:$($uri.Port)" "tcp:$($uri.Port)" }
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Port $($uri.Port) forwarded: localhost:$($uri.Port) on the emulator -> your PC."
    } else {
        # Ports below 1024 can't be bound on the device; 10.0.2.2 is the PC as seen from the emulator.
        Write-Warning "adb reverse failed ($($out.Trim())). Using 10.0.2.2 (the PC as seen from the emulator)."
        $b = [UriBuilder]$uri; $b.Host = '10.0.2.2'; $uri = $b.Uri
    }
}

# Skip Chrome's first-run screens (only applies the first time Chrome starts).
Invoke-Native {
    Invoke-Adb shell "echo 'chrome --disable-fre --no-default-browser-check --no-first-run' > /data/local/tmp/chrome-command-line"
    Invoke-Adb shell am set-debug-app --persistent com.android.chrome
} | Out-Null

$target = $uri.AbsoluteUri
$out = Invoke-Native { Invoke-Adb shell am start -a android.intent.action.VIEW -p com.android.chrome -d "'$($target -replace "'", '%27')'" }
if ($out -match 'Error') { throw "Could not open Chrome on the emulator: $($out.Trim())" }
Write-Host "Opened in the emulator: $target" -ForegroundColor Green

if (-not $NoInspector) {
    Open-Inspector
    Write-Host 'In chrome://inspect, click "inspect" under the tab to open DevTools (console, network, DOM).'
}
