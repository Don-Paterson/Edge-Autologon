<#
  Edge Auto Logon - lab deployment script

  Run from an elevated (Administrator) PowerShell window:

    irm https://raw.githubusercontent.com/Don-Paterson/Edge-Autologon/main/deploy.ps1 | iex

  You will be asked for the default username and password. To run without
  prompts, set these first:

    $env:EAL_USERNAME = 'admin'; $env:EAL_PASSWORD = 'secret'

  Or pass parameters:

    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Don-Paterson/Edge-Autologon/main/deploy.ps1))) -Username admin -Password secret -IgnoreCertErrors

  What it does:
    1. Downloads the extension from GitHub to C:\EdgeAutoLogon\extension
    2. Writes the username/password into config.js (on this PC only)
    3. Sets Edge policies so Edge fully closes and skips the first-run wizard
    4. Adds --load-extension to the Edge shortcuts (desktop, Start menu, taskbar)
    5. Restarts Edge with the extension loaded and checks that it took
#>
param(
    [string]$Username = $env:EAL_USERNAME,
    [string]$Password = $env:EAL_PASSWORD,
    [string]$InstallDir = 'C:\EdgeAutoLogon',
    [string]$Repo = 'Don-Paterson/Edge-Autologon',
    [string]$Branch = 'main',
    [string]$OpenUrl = 'http://10.1.1.1',
    # Lab use only: makes Edge ignore ALL certificate errors (self-signed certs on lab devices).
    [switch]$IgnoreCertErrors,
    [switch]$NoLaunch
)

& {
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
    function Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
    function Warn($msg) { Write-Host "    $msg" -ForegroundColor Yellow }

    # --- 0. Must be admin (writes to C:\ and HKLM policies) ---------------------
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "Please run this from PowerShell opened with 'Run as administrator'." -ForegroundColor Red
        return
    }

    $extDir = Join-Path $InstallDir 'extension'

    # --- 1. Download the extension --------------------------------------------
    Step "Downloading $Repo ($Branch) from GitHub"
    $tmp = Join-Path $env:TEMP ("eal-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $zip = Join-Path $tmp 'repo.zip'
    Invoke-WebRequest -UseBasicParsing "https://github.com/$Repo/archive/refs/heads/$Branch.zip" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $src = Get-ChildItem $tmp -Directory | Select-Object -First 1
    $srcExt = Join-Path $src.FullName 'extension'
    if (-not (Test-Path (Join-Path $srcExt 'manifest.json'))) { throw "No extension\manifest.json found in the repo." }

    # Stop Edge before replacing files it may have open.
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2

    if (Test-Path $extDir) { Remove-Item $extDir -Recurse -Force }
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item $srcExt $extDir -Recurse
    Remove-Item $tmp -Recurse -Force
    Ok "Installed to $extDir"

    # --- 2. Credentials --------------------------------------------------------
    Step "Setting username and password in config.js"
    if (-not $Username) { $Username = Read-Host '    Default username' }
    if (-not $Password) {
        $sec = Read-Host '    Default password' -AsSecureString
        $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    }
    function JsEscape($s) { $s.Replace('\', '\\').Replace('"', '\"') }
    $cfgPath = Join-Path $extDir 'config.js'
    $cfg = [IO.File]::ReadAllText($cfgPath)
    # Only touch the values inside the DEFAULTS block.
    $u = JsEscape $Username; $p = JsEscape $Password
    $cfg = [regex]::new('(const DEFAULTS = \{[\s\S]*?username:\s*")[^"]*(")').Replace($cfg, { param($m) $m.Groups[1].Value + $u + $m.Groups[2].Value }.GetNewClosure(), 1)
    $cfg = [regex]::new('(const DEFAULTS = \{[\s\S]*?password:\s*")[^"]*(")').Replace($cfg, { param($m) $m.Groups[1].Value + $p + $m.Groups[2].Value }.GetNewClosure(), 1)
    [IO.File]::WriteAllText($cfgPath, $cfg, (New-Object Text.UTF8Encoding $false))
    Ok "Done (stored in plain text in $cfgPath)"

    # --- 3. Edge policies -----------------------------------------------------
    Step "Setting Edge policies"
    $pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    New-Item -Path $pol -Force | Out-Null
    $policies = @{
        StartupBoostEnabled           = 0   # Edge must fully exit so shortcut flags apply
        BackgroundModeEnabled         = 0
        HideFirstRunExperience        = 1   # no welcome wizard on fresh lab machines
        ExtensionDeveloperModeSettings = 0  # allow developer-mode extensions
    }
    foreach ($k in $policies.Keys) { Set-ItemProperty -Path $pol -Name $k -Value $policies[$k] -Type DWord }
    Ok "Policies set"

    # --- 4. Shortcuts ----------------------------------------------------------
    Step "Adding --load-extension to Edge shortcuts"
    $edgeExe = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
                 "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
               Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $edgeExe) { throw "msedge.exe not found." }

    # DisableLoadExtensionCommandLineSwitch: newer Chromium builds ignore
    # --load-extension unless this feature is turned off.
    $flags = "--load-extension=`"$extDir`" --disable-features=DisableLoadExtensionCommandLineSwitch"
    if ($IgnoreCertErrors) { $flags += ' --ignore-certificate-errors' }

    $shortcutPaths = @(
        "$env:PUBLIC\Desktop\Microsoft Edge.lnk",
        "$env:USERPROFILE\Desktop\Microsoft Edge.lnk",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk",
        "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk",
        "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\Microsoft Edge.lnk"
    )
    $shell = New-Object -ComObject WScript.Shell
    $updated = 0
    foreach ($path in $shortcutPaths) {
        if (-not (Test-Path $path)) { continue }
        $lnk = $shell.CreateShortcut($path)
        if ($lnk.TargetPath -notlike '*msedge.exe') { continue }
        # Drop any flags from a previous run, then add the current ones.
        $existing = $lnk.Arguments -replace '--load-extension=("[^"]*"|\S+)', '' `
                               -replace '--disable-features=DisableLoadExtensionCommandLineSwitch', '' `
                               -replace '--ignore-certificate-errors', ''
        $lnk.Arguments = ("$existing $flags").Trim() -replace '\s{2,}', ' '
        $lnk.Save()
        Ok "Updated $path"
        $updated++
    }
    # Always provide one known-good shortcut on the desktop.
    $own = "$env:USERPROFILE\Desktop\Edge (Auto Logon).lnk"
    $lnk = $shell.CreateShortcut($own)
    $lnk.TargetPath = $edgeExe
    $lnk.Arguments = $flags
    $lnk.WorkingDirectory = Split-Path $edgeExe
    $lnk.Save()
    Ok "Created $own"

    # --- 5. Launch and verify --------------------------------------------------
    if ($NoLaunch) { Write-Host "`nDone. Start Edge from one of the shortcuts above." -ForegroundColor Green; return }

    Step "Starting Edge with the extension"
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    Start-Process $edgeExe -ArgumentList "$flags $OpenUrl"

    # Edge records loaded extensions in its Preferences files; give it up to 30s.
    $needle = [regex]::Escape(($extDir -replace '\\', '\\'))
    $found = $false
    for ($i = 0; $i -lt 15 -and -not $found; $i++) {
        Start-Sleep -Seconds 2
        $prefs = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default" -Filter '*Preferences' -ErrorAction SilentlyContinue
        $found = [bool]($prefs | Where-Object { (Get-Content $_.FullName -Raw) -match $needle })
    }
    if ($found) {
        Ok "Extension is loaded."
        Write-Host "`nDone. Always start Edge from a shortcut (not by clicking links in other apps)," -ForegroundColor Green
        Write-Host "or the extension won't be loaded for that session." -ForegroundColor Green
    } else {
        Warn "Couldn't confirm the extension loaded. This Edge version may ignore --load-extension."
        Warn "Load it by hand (one-off): Developer mode -> Load unpacked -> $extDir"
        Start-Process $edgeExe -ArgumentList 'edge://extensions'
        Start-Process explorer.exe $extDir
    }
}
