# Changelog

## 0.3.0, 2026-10-31

- Create the independent `windows-setup` repository from `windows-server-setup` at commit `d9210aaa77a8e01833da448ecd8a72d93a1a109d`.
- Target Windows 11 x64 workstation builds and reject Windows Server/Windows 10 before downloads.
- Remove Server-only IE Enhanced Security writes and replace the Server Start tile XML with Windows 11 Start JSON and taskbar-only XML.
- Apply empty Start pins once only on images with the supported policy capability; report manual settings for unsupported versions/editions and per-app tray icons.
- Keep Chrome, automatic WinRAR licence download, UK time zone, power preferences, sharing, optional-service management and scheduled cleanup.
- Use this repository's own installer URLs, runtime folders, manifest and Windows validation workflow.

The earlier entries below describe inherited changes from the source project.

## 0.2.1, 2026-10-31

- Integrate the configured Google Drive WinRAR licence download into the main installer and document the automatic install flow.
- Prefer local licence files, allow a URL override or download opt-out, and remove downloaded licence bytes with the installer staging directory.
- Reject sign-in/confirmation pages and truncated registration files before executing setup; add synthetic fixture checks without downloading a real licence in CI.

## 0.2.0, 2026-10-31

- Add Chrome defaults for new profiles, preserve unrelated associations, and report when an existing user still needs the Windows default-browser selection.
- Disable a narrow optional consumer-service list and save original startup types for restoration.
- Enable daily Storage Sense where available, excluding Downloads, Recycle Bin and cloud dehydration.
- Schedule Windows-managed cleanup for eligible old update files and temporary files, with pending-servicing checks and a protected SYSTEM worker.
- Add Windows tests for browser XML merging and the allowed service/cleanup scope.

## 0.1.0, 2026-10-31

- Package the consolidated Windows Server 2022 setup baseline in the source project.
- Add an online/local installer with commit-consistent downloads and SHA-256 checks.
- Remove the embedded WinRAR licence; accept a local licence file instead.
- Configure the entire discovery and sharing groups for all active supported profiles together, fixing the last-profile-wins bug.
- Keep taskbar ordering and Edge unpinning manual, matching the accepted baseline.
- Add logs, a final failure signal, a layout-policy removal script, documentation and a Windows validation workflow.

Initial GitHub release. Full Windows integration testing is still required.
