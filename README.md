# Windows Setup

One-command personal setup for **Windows 11 x64 VPS machines**, using an interactive Administrator account and 64-bit Windows PowerShell 5.1. This is an independent adaptation of [windows-server-setup](https://github.com/waqaarhussain/windows-server-setup), copied from source commit `d9210aaa77a8e01833da448ecd8a72d93a1a109d`.

## Install

Open **Windows PowerShell as Administrator** under the account whose desktop you want to configure, and paste:

```powershell
$f = "$env:TEMP\windows-setup-install.ps1"; iwr 'https://raw.githubusercontent.com/waqaarhussain/windows-setup/main/install.ps1' -UseBasicParsing -OutFile $f; powershell.exe -NoProfile -ExecutionPolicy Bypass -File $f
```

The main installer automatically downloads the configured WinRAR licence, validates its registration format and passes it to setup. After installation, setup copies it to `C:\Program Files\WinRAR\rarreg.key` and verifies the copied bytes. No Desktop licence file is required.

Rerunning gets the latest scripts and reapplies settings, including application installers. Setup does not restart or sign out automatically. Sign out and back in afterwards; some settings require a reboot. Execution-policy Bypass applies only to the child process and cannot override enforced Group Policy.

## Included settings

| Setting | Windows 11 behaviour |
| --- | --- |
| Chrome | Stable x64 enterprise MSI from Google, with vendor signature verification |
| WinRAR | English stable x64 release from RARLAB, with signature verification and automatic licence copy |
| Chrome defaults | Preserves unrelated mappings and imports browser defaults for new profiles; opens Default apps if the current user still needs to select Chrome |
| Time zone | GMT Standard Time, including UK daylight-saving rules |
| Power | High Performance where available; no AC/DC display or standby timeout |
| Scaling | Carries over the blurry-app preference; verify behaviour on the installed build |
| Start preferences | Disables usage/recent-item preferences and configures hiding Recently added |
| Start pins | Windows 11 JSON with an empty pinned list, applied once where the supported GPO capability is present |
| Taskbar | Taskbar-only XML including Chrome; existing order and removing Edge may remain manual |
| Tray icons | Reports the per-app Windows 11 setting under Personalisation > Taskbar > Other system tray icons |
| Discovery/sharing | Entire firewall groups and dependency services for detected active profiles, including Public |
| Notifications | Inherited toast/app-notification preferences disabled |
| Optional services | Fax, offline maps, retail demo, Windows Media Player library sharing and Xbox services; original startup settings saved |
| Storage | Daily Storage Sense where available and native Windows update/temp cleanup at 03:30 local time |

The Server-only IE Enhanced Security step is **Not applicable** and makes no IE ESC registry changes.

## Windows 11 compatibility and shell limits

Workstation build 22000 or later and AMD64 are required. Windows Server, Windows 10 and ARM64 are rejected before downloads. Pro/Enterprise/Education are the intended editions for managed policies. Home can run the other steps, but policy-controlled settings may remain manual.

Windows 11 Start pins use JSON rather than the Server tile layout. The Configure Start Pins GPO is supported from Windows 11 24H2 with KB5062660. Setup checks build 26100 or later, a non-Home edition and that policy's presence in the installed StartMenu.admx. Missing capability reports **Manual setting**. It does not modify Start's internal database. All apps remains available; Start is not forced to open directly into an alphabetical list.

On capable images, Start pin policy points to the JSON and applies at sign-in. The empty list applies once so later user changes can persist. Domain policy can override local settings. Existing user-pinned taskbar apps may remain; Chrome-first order and removal of Edge are not guaranteed. Actual UI behaviour requires a VPS test.

Remove this toolkit's current-user shell policies with:

```powershell
& 'C:\ProgramData\WindowsSetup\Disable-CustomLayout.ps1'
```

This removes ConfigureStartPins, StartLayoutFile and LockedStartLayout, then requires sign-out/sign-in. It does not restore old pins or undo other settings. An initial Explorer policy export is retained where one existed.

Chrome's current-user default may require **Settings > Apps > Default apps > Google Chrome > Set default**. That step reports **Needs action**, rather than claiming that a policy write changed the browser.

## WinRAR licence

The configured Google Drive download URL is visible in this public repo; licence bytes are not committed. The file must be accessible without signing in. HTML sign-in/confirmation pages and truncated files are rejected before setup. Format validation does not establish licence validity. The temporary download is removed on completion or failure.

A local rarreg.key beside install.ps1 or on the Desktop takes priority. Options:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -WinRARLicensePath 'C:\Private\rarreg.key'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -WinRARLicenseUrl 'https://your-direct-download-url'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -SkipWinRARLicenseDownload
```

Skipping the download still allows a detected local licence. Otherwise an existing installed licence is preserved. Licence and certificate files are excluded by .gitignore.

## Services, sharing and cleanup

Optional service names: Fax, MapsBroker, RetailDemo, WMPNetworkSvc, XblAuthManager, XblGameSave, XboxNetApiSvc and XboxGipSvc. Missing services and those with running dependents are skipped. This assumes those optional features are unused on the VPS. RDP, Defender, Windows Update, printing, storage and discovery/SMB services are excluded. No particular performance gain is promised.

Restore saved startup types, restarting services that originally ran:

```powershell
& 'C:\ProgramData\WindowsSetup\Restore-OptionalServices.ps1'
```

Sharing configures all profiles active during setup, including Public. Inbound discovery/sharing rules are scoped to LocalSubnet before enabling; native outbound/multicast scopes are preserved. Network categories and RDP rules are unchanged. There is no watcher for later profile changes. Access from other remote networks requires a separate explicit firewall-scope decision. Setup does not create shares or change the provider firewall.

Storage Sense cleans unused temporary files daily, excluding Downloads, Recycle Bin and cloud-file dehydration. If unavailable, setup reports the Disk Cleanup fallback.

WindowsSetup-StorageCleanup runs as SYSTEM at **03:30 local time**, or when next available. Only installed Windows Disk Cleanup handlers for update cleanup, temporary files, temporary setup files and Delivery Optimization files are selected. The existing component-cleanup task starts if ready. Cleanup defers for pending servicing restarts, known servicing processes, busy Windows Update or unreadable update state. Windows decides file eligibility. It does not manually wipe SoftwareDistribution/WinSxS or use DISM /ResetBase. No cleanup runs during setup. Only Administrators and SYSTEM can write the privileged worker directory.

## Logs, local package and validation

Logs/CSV results: `C:\ProgramData\WindowsSetup\Logs`. Steps report Applied, sign-in/manual action, fallback or failure. Failures allow remaining steps to finish, then produce a final error. Check the UI after sign-in.

Download/extract this repository's ZIP for local package use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -FromLocalPackage
```

Internet remains necessary for application installers and the licence download, unless overridden. Downloads come from one resolved commit and are checked against manifest SHA-256 values. The bootstrap and manifest share the repository's trust; this detects inconsistent/corrupted files, not repository compromise.

Windows CI parses scripts, checks hashes and shell assets, tests OS/capability gates, preserves unrelated browser mappings and rejects synthetic invalid licence downloads. It does not apply system settings or download a real licence. Full installation has **not** been tested on the target Windows 11 VPS.

Update manifest.json when package scripts/assets change, using hashes of exact UTF-8/LF tracked bytes.

References: [Start layout](https://learn.microsoft.com/en-us/windows/configuration/start/layout), [taskbar pins](https://learn.microsoft.com/en-us/windows/configuration/taskbar/pinned-apps), [Storage Sense](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-storage), [component cleanup](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/clean-up-the-winsxs-folder).

Registry writes open/create keys without replacing them, and update only the requested values. Regression tests preserve existing values and child keys across repeated writes. This prevents further resets; it cannot reconstruct unrelated settings that an earlier toolkit run may already have removed. Failed steps are also printed in full after the results table.
