# Security Policy

## Reporting Security Issues

Please do not open a public GitHub issue for a security vulnerability.

Report security concerns privately to the repository maintainer. Include a clear description, affected version or commit, reproduction steps, and any impact you can confirm without accessing systems you do not own or administer.

## Proxmox VE API Token Guidance

PVE Viewer can store a Proxmox VE API token locally so it can fetch resource summaries and send VM/LXC start, stop, and restart actions.

Recommended token practices:

- Create a dedicated token for PVE Viewer.
- Grant only the permissions required for the actions you use.
- Prefer read-only permissions if you only need resource summaries.
- Avoid administrator, root, or broad personal tokens.
- Rotate the token if your Mac, backups, or local app data may have been exposed.
- Delete unused tokens from Proxmox VE.

Token secrets are stored on the local Mac in the app's Application Support directory as `APITokens.json` with owner-only file permissions. The app does not sync these secrets or include them in the repository.

## Supported Versions

This project is preparing its first public release. Security fixes should target the current `main` branch until a versioned release process exists.

## Independence Disclaimer

PVE Viewer is an independent project and is not affiliated with, endorsed by, sponsored by, or otherwise associated with Proxmox Server Solutions GmbH.
