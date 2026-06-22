# Contributing

Thanks for helping improve PVE Viewer.

## Local Setup

Requirements:

- macOS 13.0 or later.
- Xcode with the macOS SDK.

Build the app:

```sh
xcodebuild -project PVEViewer.xcodeproj -scheme PVEViewer -configuration Debug -derivedDataPath .build/DerivedData build
```

Run the local debug app:

```sh
./script/build_and_run.sh
```

Run tests:

```sh
xcodebuild -project PVEViewer.xcodeproj -scheme PVEViewer -configuration Debug -derivedDataPath .build/DerivedData test
```

## Pull Requests

- Keep changes focused.
- Do not commit saved Proxmox VE instances, hostnames, IP addresses, API tokens, token secrets, local paths, build output, or Xcode user data.
- Use fixture values such as `pve.example.com`, `fixture-token-value`, or documentation-reserved IP addresses when tests need examples.
- Keep references to Proxmox VE descriptive and avoid using Proxmox logos or branding as app identity.
- Keep release packaging changes out of normal pull requests unless the maintainer explicitly asks for them.

## License

By contributing, you agree that your contributions are licensed under the MIT License.
