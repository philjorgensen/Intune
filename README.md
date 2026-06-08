# Intune

This repository contains Lenovo Intune and Autopilot deployment content, including BIOS certificate authentication automation, remediation scripts, and Win32 app packaging guidance.

## Repository structure

- `Autopilot/` - Scripts and source content used in Windows Autopilot deployments.
  - `BiosCertificateAuth/` - Certificate-based BIOS authentication scripts and supporting documentation.
  - `Lenovo-Client-Update/` - Win32 app wrapper around the Lenovo.Client.Update (LCU) module to install drivers, firmware, and BIOS during Autopilot pre-provisioning.
  - `System Update/` - Autopilot-related update scripts and deployment helpers.
  - `Thin Installer/` - Thin installer resources for Autopilot scenarios.
  - `ThinkBiosConfig/` - Think BIOS configuration tooling and sample files.

- `Remediations/` - Scripts and automation designed to remediate device configuration issues and manage endpoint state.
  - `Apps/` - Remediation apps and helper scripts.
  - `Asset Tag/` - Asset tag management and reporting automation.

- `Win32 Apps/` - Intune Win32 app packaging and deployment content.
  - `Commercial_Vantage/` - Packaging for Lenovo Commercial Vantage.
  - `Intel_PPM/` - Intel Platform Power Management packaging and deployment scripts.
  - `ThinkBiosConfigTool/` - Packaging for Think BIOS Config Tool deployments.

## Usage

Use the folders in this repository to support Windows Autopilot and Intune deployments for Lenovo devices. Scripts are typically packaged as Win32 apps or used as remediation content within Intune.

## Notes

- Review each folder for specific script details and any included documentation.
- The `BiosCertificateAuth` folder includes a detailed `README.md` on certificate-based BIOS authentication in Autopilot.
- Keep deployment scripts up to date with current Intune and device management practices.
