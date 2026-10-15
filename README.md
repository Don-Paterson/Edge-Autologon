# Edge-Autologon

Microsoft Edge extension that automatically logs in to lab devices
(10.1.1.1, .2, .3, .4, .101, .111, .130), plus a one-line deployment script.

## Deploy to a new lab machine

Open **PowerShell as Administrator** and run:

```powershell
irm https://raw.githubusercontent.com/Don-Paterson/Edge-Autologon/main/deploy.ps1 | iex
```

You'll be asked for the default username and password. The password is also
used as the Check Point SIC activation key (override with `-SicKey`). The script then:

1. Downloads `extension/` from this repo to `C:\EdgeAutoLogon\extension`
2. Writes the username/password and SIC key into `config.js` on that machine only
3. Sets Edge policies (no startup boost/background mode, no first-run wizard)
4. Adds `--load-extension` to the Edge desktop / Start menu / taskbar shortcuts
   and creates an **Edge (Auto Logon)** shortcut on the desktop
5. Restarts Edge with the extension loaded and checks that it worked

### No prompts

```powershell
$env:EAL_USERNAME = 'admin'; $env:EAL_PASSWORD = 'secret'
irm https://raw.githubusercontent.com/Don-Paterson/Edge-Autologon/main/deploy.ps1 | iex
```

### With options

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Don-Paterson/Edge-Autologon/main/deploy.ps1))) `
    -Username admin -Password secret -IgnoreCertErrors -OpenUrl https://10.1.1.2
```

| Option | Meaning |
|---|---|
| `-Username` / `-Password` | Default login used for every site |
| `-SicKey` | SIC activation key filled into the First Time Wizard (not submitted). Defaults to the password |
| `-IgnoreCertErrors` | **Lab only.** Edge ignores all certificate errors (self-signed device certs) |
| `-OpenUrl` | Page to open after deployment (default `http://10.1.1.1`) |
| `-InstallDir` | Install folder (default `C:\EdgeAutoLogon`) |
| `-NoLaunch` | Don't restart Edge at the end |

## Notes

- **Never commit real passwords.** This repo is public; `config.js` here keeps
  `CHANGE_ME` and the script fills in the real values on each machine.
- Edge must be started from a shortcut for the extension to load. Edge windows
  opened by other apps (e.g. clicking a link in Outlook when Edge isn't running)
  start without it.
- Edge updates can reset the Start menu shortcut; re-run the script if needed.
- If the script reports it couldn't confirm the extension loaded, load it once by
  hand: `edge://extensions` → Developer mode → **Load unpacked** → `C:\EdgeAutoLogon\extension`.

## Auto-filled fields (no submit)

`AUTOFILL` in `extension/config.js` lists fields that are filled in whenever they
appear, without clicking anything - currently the First Time Wizard's
**Activation Key** and **Confirm Activation Key**. Fields are matched by their
on-screen label (or a CSS `selector`), so add more the same way.

## Adding a site

1. `extension/manifest.json`: add `"*://IP/*"` to `host_permissions` and `content_scripts.matches`
2. `extension/config.js`: add `{ host: "IP" }` to `SITES` (override `type`, `username`, etc. if different)
