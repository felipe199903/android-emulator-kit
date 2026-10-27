# Installs SDK, system image and AVD. Idempotent, no admin.
. "$PSScriptRoot\config.ps1"

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

function Expand-Download($url, $dest) {
    $zip = Join-Path $env:TEMP ([IO.Path]::GetRandomFileName() + '.zip')
    $req = @{ Uri = $url; OutFile = $zip; UseBasicParsing = $true }
    if ($Proxy) { $req.Proxy = $Proxy; $req.ProxyUseDefaultCredentials = $true }
    Invoke-WebRequest @req
    Expand-Archive $zip $dest -Force
    Remove-Item $zip
}

# 1. Java 17+
Step 'Java'
$java = Get-Command java -ErrorAction SilentlyContinue
$javaOk = $java -and ((Invoke-Native { java -version }) -match 'version "(\d+)') -and [int]$Matches[1] -ge 17
$portableJdk = Get-ChildItem (Join-Path $KitHome 'jdk') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $javaOk -and -not $portableJdk) {
    Write-Host 'Java 17+ not found; downloading a portable JDK (zip, no admin)...'
    Expand-Download $JdkUrl (Join-Path $KitHome 'jdk')
    $portableJdk = Get-ChildItem (Join-Path $KitHome 'jdk') -Directory | Select-Object -First 1
}
if ($portableJdk) {
    $env:JAVA_HOME = $portableJdk.FullName
    $env:PATH = "$($portableJdk.FullName)\bin;$env:PATH"
}

# 2. Corporate CA (SSL inspection): a kit-local copy of the truststore, so the system JDK is never modified
if ($CorpCaCert) {
    Step 'Corporate certificate'
    $javaHome = if ($env:JAVA_HOME) { $env:JAVA_HOME } else { Split-Path (Split-Path (Get-Command java).Source) }
    $store = Join-Path $KitHome 'cacerts'
    New-Item -ItemType Directory -Force $KitHome | Out-Null
    Copy-Item (Join-Path $javaHome 'lib\security\cacerts') $store -Force
    & keytool -importcert -noprompt -alias corp-ca -file $CorpCaCert -keystore $store -storepass changeit
    if ($LASTEXITCODE -ne 0) { throw "keytool failed to import $CorpCaCert" }
    $env:JAVA_TOOL_OPTIONS = "-Djavax.net.ssl.trustStore=$store -Djavax.net.ssl.trustStorePassword=changeit"
}

# 3. Current cmdline-tools (ship the Android CLI, `android.exe`; the old sdkmanager can't unpack new images)
Step 'Android cmdline-tools'
$toolsDir   = Join-Path $SdkRoot 'cmdline-tools'
$latest     = Join-Path $toolsDir 'latest'
$androidCli = Join-Path $latest 'bin\android.exe'
$avdmanager = Join-Path $latest 'bin\avdmanager.bat'
$proxyArgs  = if ($Proxy) { @('--proxy=http', "--proxy_host=$($Proxy.Host)", "--proxy_port=$($Proxy.Port)") } else { @() }
if (-not (Test-Path $androidCli)) {
    # Bootstrap: use an old cmdline-tools (existing or downloaded) only to install `cmdline-tools;latest`.
    $bootstrap = Join-Path $toolsDir 'bootstrap'
    if (Test-Path $latest) { Move-Item $latest $bootstrap }
    elseif (-not (Test-Path $bootstrap)) {
        Expand-Download $CmdlineToolsUrl $toolsDir
        Move-Item (Join-Path $toolsDir 'cmdline-tools') $bootstrap
    }
    $oldSdkmanager = Join-Path $bootstrap 'bin\sdkmanager.bat'
    Invoke-Native { 1..20 | ForEach-Object { 'y' } | & $oldSdkmanager --licenses @proxyArgs } | Out-Null
    & $oldSdkmanager --install 'cmdline-tools;latest' @proxyArgs
    if (-not (Test-Path $androidCli)) { throw 'Failed to install cmdline-tools;latest (network/proxy/certificate? see the README)' }
    Remove-Item $bootstrap -Recurse -Force
}

# 4. User-scope environment variables
Step 'Environment variables (user)'
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $SdkRoot, 'User')
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User') -split ';' | Where-Object { $_ }
$wanted = @("$SdkRoot\platform-tools", "$SdkRoot\emulator", "$SdkRoot\cmdline-tools\latest\bin")
$missing = $wanted | Where-Object { $_ -notin $userPath }
if ($missing) { [Environment]::SetEnvironmentVariable('PATH', (($userPath + $missing) -join ';'), 'User') }

# 5. SDK packages
Step "SDK packages ($SystemImage)"
# The Android CLI uses '/' as the package name separator.
& $androidCli "--sdk=$SdkRoot" sdk install platform-tools emulator ($SystemImage -replace ';', '/')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Emulator)) { throw 'Package install failed (network/proxy/certificate? see the README)' }

# 6. Hardware acceleration
Step 'Acceleration (WHPX)'
$accel = Invoke-Native { & $Emulator -accel-check }
Write-Host $accel.Trim()
if ($accel -notmatch 'is installed and usable') {
    Write-Host ''
    Write-Host 'Acceleration unavailable. Enable the Windows feature "Windows Hypervisor Platform" and reboot' -ForegroundColor Yellow
    Write-Host '(needs admin, ask IT if necessary):' -ForegroundColor Yellow
    Write-Host 'Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform' -ForegroundColor Yellow
    exit 1
}

# 7. AVD
Step "AVD $AvdName"
$avdList = & $Emulator -list-avds
if ($avdList -notcontains $AvdName) {
    'no' | & $avdmanager create avd -n $AvdName -k $SystemImage -d $AvdDevice
    if ($LASTEXITCODE -ne 0) { throw 'avdmanager failed' }
}
$ini = Join-Path $AvdHome "$AvdName.avd\config.ini"
$settings = [ordered]@{ 'hw.ramSize' = "$AvdRamMb"; 'hw.keyboard' = 'yes'; 'hw.gpu.enabled' = 'yes'; 'hw.gpu.mode' = 'auto' }
$lines = Get-Content $ini | Where-Object { ($_ -split '=', 2)[0].Trim() -notin $settings.Keys }
$lines + ($settings.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) | Set-Content $ini -Encoding ascii

Write-Host ''
Write-Host 'Done. Run .\start.ps1 or .\open.ps1 <url> (open a new terminal to pick up the updated PATH).' -ForegroundColor Green
