# ReCovery-USB-Creator

A PowerShell GUI tool for IT technicians and MSPs that builds bootable WinPE-based USB recovery drives — with optional Windows 11 installation image and driver injection for bare-metal restores.

> **This tool wipes USB drives and can optionally wipe the target PC's primary hard drive during restore. Read this document before running it.**

---

## What It Does

ReCovery-USB-Creator automates the process of building a WinPE recovery USB. Select your USB drive, click a button, and get a consistent bootable drive every time — no manual ADK steps required.

The tool downloads and installs the Windows ADK automatically if it is not already present.

**Built for help desk technicians who need reliable recovery media on demand.**

---

## How to Run

1. Download `ReCovery-USB-Creator.ps1`
2. Right-click the file → **Run with PowerShell**
3. When prompted by UAC, click **Yes**
4. Select your USB drive from the dropdown and click **Create ReCoveryUSB**

**If PowerShell blocks the script:**

```powershell
# Run once in an elevated PowerShell window, then try again
Unblock-File -Path .\ReCovery-USB-Creator.ps1
```

Or right-click the file → Properties → check **Unblock** → OK.

---

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or later
- Run as Administrator (the script will not launch without it)
- A USB drive — **8 GB minimum**, 16 GB recommended if including a Windows installation image
- Internet connection only if the Windows ADK is not already installed

---

## What the Buttons Do

**USB-PREP** — Wipes and reformats a USB drive as NTFS/MBR. Use this if the main creation process fails on a stubborn drive.

**Create ReCoveryUSB** — Runs the full three-phase build:

| Phase | What happens |
|-------|-------------|
| 1 | Installs Windows ADK if needed. Copies base WinPE image, exports third-party drivers from your PC, injects them into WinPE, writes a custom boot menu. |
| 2 | Wipes and formats the USB drive, makes it bootable, copies all WinPE files. The drive is usable as a recovery tool at this point. |
| 3 | (Optional) Prompts for a Windows 11 ISO. If provided, extracts the install image, lets you pick a Windows edition, injects your PC's drivers, and copies everything to the USB. |

**Cancel** — Stops the operation at the next safe checkpoint and cleans up temporary files.

---

## What the Finished USB Does

When booted on a target PC, the USB presents a menu:

- **[1] Automated Windows 11 Restore** — Wipes Disk 0, partitions it GPT/UEFI, applies the Windows image, and configures boot files
- **[2] Recovery Command Prompt** — Opens a command prompt for manual repairs
- **[3] Reboot**

> **Disk 0 warning:** The restore script targets Disk 0 (the first internal drive). On systems with multiple internal drives, run `diskpart` → `list disk` to confirm which disk is Disk 0 before starting a restore.

---

## Working Directory

The script uses `C:\USB\` for temporary files during the build. This folder is cleaned up after each successful run. The session log is saved to `C:\USB\winpe_creation.log`.

---

## Notes

- Driver injection exports drivers from the PC used to build the USB. For best results, build on the same model you intend to restore.
- The ADK installers are cached in `C:\USB\` after the first download — subsequent runs skip the download step.

---

## Version History

| Version | Notes |
|---------|-------|
| 4.2 | Fixed missing `$parentForm` on confirmation dialogs; fixed exFAT → NTFS (bootsect.exe requirement); replaced deprecated `Get-WmiObject` with `Get-CimInstance`; added placeholder fallback when no ISO selected; added 8 GB minimum drive size check; added Fixed disk safety check to Create path; added Cancel button; added elapsed time display; UI stays responsive during long DISM operations |
| 4.1 | Initial public release |

---

## License

MIT — free to use, modify, and distribute.

---

## Imara — AI-Native IT Management for MSPs

If you manage endpoints for a living, Imara is being built for you.

Imara is an AI-native RMM platform that uses Claude AI to monitor, diagnose, and remediate endpoint issues automatically — 24 hours a day, across your entire fleet.

**Currently in development. Early access signups open now.**

[Join the waitlist at tryimaratech.com](https://tryimaratech.com)
