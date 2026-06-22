# PVE Viewer

PVE Viewer is a macOS SwiftUI app for keeping an eye on Proxmox VE instances from a native desktop interface. It lets you save instance links, open the Proxmox VE web UI in an embedded browser, check reachability, and optionally use a Proxmox VE API token to show resource information and send basic VM/LXC actions.

PVE Viewer is released under the MIT License.

## Current Features

- Save one or more Proxmox VE instance links.
- Normalize bare hostnames and IP addresses to HTTPS on port 8006.
- Validate that a saved link looks like a Proxmox VE server.
- Allow self-signed HTTPS certificates per instance.
- Open the selected instance in an embedded WebKit view.
- Refresh instance reachability from the main window or menu bar.
- Optional API token support for cluster CPU, memory, storage, node, VM, and LXC resource summaries.
- Start, stop, and restart VM/LXC resources through the Proxmox VE API.
- Menu bar access for saved instances, refresh, API settings, and resource actions.

## Screenshots

Screenshots will be added after the first public build is verified.

## Requirements

- macOS 13.0 or later.
- Xcode with the macOS SDK to build from source.
- Access to a Proxmox VE server for normal use.
- A Proxmox VE API token only if you want API-backed resource summaries and VM/LXC actions.

## Build From Source

Clone the repository, open `PVEViewer.xcodeproj` in Xcode, then build and run the `PVEViewer` scheme.

You can also build from Terminal:

```sh
xcodebuild -project PVEViewer.xcodeproj -scheme PVEViewer -configuration Debug -derivedDataPath .build/DerivedData build
```

To run the local debug app with the included helper:

```sh
./script/build_and_run.sh
```

To run tests:

```sh
xcodebuild -project PVEViewer.xcodeproj -scheme PVEViewer -configuration Debug -derivedDataPath .build/DerivedData test
```

## API Token And Security Notes

API tokens are optional. Without a token, PVE Viewer can still save instance links, check basic reachability, and open the Proxmox VE web UI.

When you do configure an API token, create a dedicated Proxmox VE token with the narrowest permissions needed for what you plan to use in the app. Avoid reusing administrator credentials or broad personal tokens.

Token secrets are saved locally on your Mac in the app's Application Support folder as `APITokens.json` with owner-only file permissions. Saved instance metadata is stored in macOS `UserDefaults`; token secrets are not stored in the instance list.

## Local Data

PVE Viewer stores saved instance metadata locally on the Mac running the app.

## Independence Disclaimer

PVE Viewer is an independent project and is not affiliated with, endorsed by, sponsored by, or otherwise associated with Proxmox Server Solutions GmbH. "Proxmox VE" is used only to describe compatibility with the Proxmox Virtual Environment platform.
