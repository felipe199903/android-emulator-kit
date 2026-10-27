# Android Emulator Kit

**Debug your site in a real Android Chrome, with full DevTools, from one PowerShell command.**
No Android Studio, no admin rights, works behind corporate proxies and SSL inspection.

> **Windows only** (PowerShell 5.1+, Windows Hypervisor Platform). [Leia em português](README.pt-BR.md).

```powershell
.\setup.ps1                  # once: downloads SDK + Android 15 image (~1.5 GB), creates the emulator
.\open.ps1 localhost:3000    # boots the emulator, opens your dev server in its Chrome, opens chrome://inspect on your PC
```

<!-- Demo GIF: record setup -> open -> DevTools and save it as docs/demo.gif, then uncomment:
![demo](docs/demo.gif)
-->

## Why

- **Your `localhost` just works on the phone.** `open.ps1` tunnels the port with `adb reverse`, so the page keeps the
  `localhost` origin (secure context: service workers, geolocation, camera, etc.).
- **Release-build WebViews are inspectable.** The image is `google_apis` (*userdebug*), so WebViews in any app show up in
  `chrome://inspect`, not only debuggable builds.
- **Everything stays in your user profile.** A portable JDK is downloaded if you don't have Java 17+. The only step that
  may need IT is enabling the hypervisor.
- **Corporate networks are first-class.** Proxy and custom root CA support, without touching the system Java install.

If you already use Android Studio's Device Manager, you don't need this kit.

## Requirements (once)

1. **Windows Hypervisor Platform** enabled (needs admin, and a reboot):
   `Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform`.
   `setup.ps1` checks it and tells you if it's missing.
2. ~8 GB free disk space (SDK + image + AVD).
3. Corporate network? Set these in the same terminal before running setup:
   ```powershell
   $env:HTTPS_PROXY  = 'http://proxy.company:8080'     # if there is a proxy
   $env:CORP_CA_CERT = 'C:\certs\company-root-ca.cer'  # if the network does SSL inspection
   ```
   To get the certificate: open any HTTPS site in your browser → padlock → Certificate → export the **root** certificate
   (Base-64 .cer).

If PowerShell refuses to run downloaded scripts, unblock the folder: `Get-ChildItem -Recurse | Unblock-File`.

## Usage

### Debug a website

```powershell
.\open.ps1 localhost:3000            # your dev server (port forwarded automatically)
.\open.ps1 https://example.com       # any public URL
.\open.ps1 localhost:5173 -NoInspector
```

Then click **inspect** under the tab in `chrome://inspect` (Edge is used if Chrome isn't installed) to get console,
network, DOM and performance tools for the page running on Android.

Ports below 1024 (e.g. `localhost:80`) can't be forwarded; the script falls back to `10.0.2.2`, the PC as seen from the
emulator.

### Emulator

```powershell
.\start.ps1              # boot (no-op if already running); -Wipe factory-resets, -Headless runs without a window
```

The kit always uses `emulator-5554`, so it keeps working with a physical phone plugged in.

### Debug an app

```powershell
.\inspect.ps1 webview -Package com.example.app  # checks for active WebViews and opens chrome://inspect
.\inspect.ps1 logs    -Package com.example.app  # logcat for the app only, saved to out\ (survives app restarts)
.\inspect.ps1 crash                             # recent crashes + ANRs with stack traces
.\inspect.ps1 ui                                # UI tree (XML) + screenshot in out\
.\inspect.ps1 record                            # screen recording (Enter to stop)
```

- Find the package name with `adb shell pm list packages -3`.
- Pure **React Native / Flutter** apps have no WebView; use `ui`, `logs` and `crash`.
- Drag an `.apk` onto the emulator window to install it.

### Install a beta from Firebase App Distribution

1. In the emulator, open **Chrome** and sign in with the Google account invited to the beta.
2. Open the link from the Firebase invite e-mail → accept → download and install **App Tester**.
3. Install the build from App Tester.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `accel-check` fails | Enable *Windows Hypervisor Platform* and reboot |
| `Error on ZipFile unknown archive` | Old `cmdline-tools` (≤ 12) can't unpack new images. Run `setup.ps1`, which upgrades to the Android CLI |
| SSL/PKIX download error | Set `CORP_CA_CERT` and run `setup.ps1` again |
| Download fails / times out | Set `HTTPS_PROXY`; ask IT to allow `dl.google.com` and `api.adoptium.net` |
| Boot does not finish | `.\start.ps1 -TimeoutSec 600` on slow machines; otherwise `.\start.ps1 -Wipe` |
| App closes or says "device not supported" | The app uses Play Integrity / emulator detection; only works on a physical device |
| Emulator is slow | Close other VMs; check GPU `auto` and 4 GB RAM in `~\.android\avd\beta-tester.avd\config.ini` |
| Messy state | `.\start.ps1 -Wipe` |

## What setup changes on your machine

- Android SDK in `%LOCALAPPDATA%\Android\Sdk` (or `ANDROID_HOME`), AVD in `~\.android\avd`.
- Portable JDK and corporate truststore copy (if needed) in `%LOCALAPPDATA%\android-kit`.
- User-scope `ANDROID_HOME` and `PATH` entries for `platform-tools`, `emulator` and `cmdline-tools`.

## Configuration

Android version, AVD name, RAM, emulator port etc. live in [`config.ps1`](config.ps1).

## License

[MIT](LICENSE)
