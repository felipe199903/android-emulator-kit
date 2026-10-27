# Boots the emulator (if it isn't running yet) and waits for boot to complete.
param(
    [switch]$Wipe,              # factory-reset the AVD
    [switch]$Headless,          # no window
    [int]$TimeoutSec = 300
)
. "$PSScriptRoot\config.ps1"

$running = (Invoke-Native { Invoke-Adb get-state }).Trim() -eq 'device'
if ($running -and $Wipe) { throw "Emulator $Serial is already running; close it before using -Wipe." }

$proc = $null
if ($running) {
    Write-Host "Emulator $Serial is already running."
} else {
    $emuArgs = @('-avd', $AvdName, '-port', $EmulatorPort, '-netdelay', 'none', '-netspeed', 'full')
    if ($Wipe)     { $emuArgs += '-wipe-data' }
    if ($Headless) { $emuArgs += '-no-window' }
    if ($Proxy)    { $emuArgs += @('-http-proxy', "$($Proxy.Host):$($Proxy.Port)") }
    $proc = Start-Process $Emulator -ArgumentList $emuArgs -WindowStyle Minimized -PassThru
}

Write-Host 'Waiting for boot...'
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while (-not (Test-EmulatorBooted)) {
    if ($proc -and $proc.HasExited) { throw "The emulator exited during boot (code $($proc.ExitCode)). Try .\start.ps1 -Wipe or run .\setup.ps1 again." }
    if ((Get-Date) -gt $deadline) { throw "Boot did not finish within $TimeoutSec s. Use -TimeoutSec to wait longer." }
    Start-Sleep 2
}
Write-Host "Emulator $Serial ready." -ForegroundColor Green
