# ReCovery USB Creator

A PowerShell tool for IT technicians and MSPs that builds bootable WinPE-based USB recovery drives — fast, repeatable, and scriptable.

## What It Does

ReCovery USB Creator automates the process of creating a WinPE bootable USB recovery drive. Instead of manually stepping through the Windows ADK tools each time, run a single script and get a consistent, ready-to-use recovery drive every time.

Built for help desk technicians who need reliable recovery media on demand.

## Requirements

- Windows 10 or Windows 11
- Windows Assessment and Deployment Kit (ADK) with WinPE add-on installed
- A USB drive (8 GB minimum recommended)
- PowerShell 5.1 or later
- Run as Administrator

## Usage

```powershell
.\Create-RecoveryUSB.ps1 -DriveLetter E
```

## Parameters

| Parameter | Required | Description |
|---|---|---|
| `-DriveLetter` | Yes | Drive letter of the target USB drive |
| `-OutputLabel` | No | Volume label for the finished drive (default: RECOVERY) |

## Notes

- All data on the target USB drive will be erased
- Run PowerShell as Administrator or the script will exit early
- Tested on Windows 10 21H2 and Windows 11 22H2 and later

## Contributing

Issues and pull requests welcome. If you find a bug or have a feature request, open an issue.

## License

MIT — free to use, modify, and distribute.

---

## Imara — AI-Native IT Management for MSPs

If you manage endpoints for a living, Imara is being built for you.

Imara is an AI-native RMM platform that uses Claude AI to monitor, diagnose, and remediate endpoint issues automatically — 24 hours a day, across your entire fleet. No more chasing alerts. No more reactive firefighting.

**Currently in development. Early access signups open now.**

[Join the waitlist at tryimaratech.com](https://tryimaratech.com)
