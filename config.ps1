# Shared values for the kit's scripts. Dot-source: . "$PSScriptRoot\config.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ApiLevel    = 35
# google_apis (no Play Store): has Play Services and is userdebug -> inspectable WebViews and adb root.
$SystemImage = "system-images;android-$ApiLevel;google_apis;x86_64"
$AvdName     = 'beta-tester'
$AvdDevice   = 'pixel_7'
$AvdRamMb    = 4096
# Fixed console port so every adb call targets this emulator, even with a phone plugged in.
$EmulatorPort = 5554
$Serial       = "emulator-$EmulatorPort"

$SdkRoot  = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
$KitHome  = Join-Path $env:LOCALAPPDATA 'android-kit'   # portable JDK and truststore, if needed
$OutDir   = Join-Path $PSScriptRoot 'out'
$AvdHome  = if ($env:ANDROID_AVD_HOME) { $env:ANDROID_AVD_HOME }
            elseif ($env:ANDROID_USER_HOME) { Join-Path $env:ANDROID_USER_HOME 'avd' }
            else { Join-Path $env:USERPROFILE '.android\avd' }

# Only used to bootstrap the first install; setup then upgrades to `cmdline-tools;latest`.
# If Google removes this build, take the current link from https://developer.android.com/studio#command-tools
$CmdlineToolsUrl = 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip'
$JdkUrl          = 'https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse'

# Corporate network: HTTPS_PROXY=http://host:port and CORP_CA_CERT=C:\path\ca.cer (both optional)
$Proxy = if ($env:HTTPS_PROXY) { [Uri]$env:HTTPS_PROXY } else { $null }
$CorpCaCert = $env:CORP_CA_CERT

$AdbExe   = Join-Path $SdkRoot 'platform-tools\adb.exe'
$Emulator = Join-Path $SdkRoot 'emulator\emulator.exe'

# Runs a native command and returns stdout+stderr as text, without stderr becoming an exception (PowerShell 5.1).
function Invoke-Native([scriptblock]$Block) {
    $ErrorActionPreference = 'Continue'
    & $Block 2>&1 | ForEach-Object { "$_" } | Out-String
}

# adb pinned to the kit's emulator.
function Invoke-Adb { & $AdbExe -s $Serial @args }

function Test-EmulatorBooted {
    (Invoke-Native { Invoke-Adb shell getprop sys.boot_completed }).Trim() -eq '1'
}

# Opens the DevTools device list in Chrome (or Edge, if Chrome isn't installed).
function Open-Inspector {
    try { Start-Process 'chrome.exe' 'chrome://inspect/#devices' }
    catch { Start-Process 'msedge.exe' 'edge://inspect/#devices' }
}

$env:ANDROID_HOME = $SdkRoot
$env:ANDROID_SDK_ROOT = $SdkRoot
