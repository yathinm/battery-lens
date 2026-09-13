# BatteryLens

BatteryLens is a native macOS menu-bar utility for viewing battery state from the Mac and supported nearby devices. It stores normalized readings locally, requests permissions only for enabled capabilities, and keeps trusted-Mac sharing opt-in.

## Build

Requirements: Xcode 16 or newer, macOS 11 deployment SDK, and XcodeGen for regenerating the project from `project.yml`.

```sh
xcodegen generate
swift test
xcodebuild -project BatteryLens.xcodeproj -scheme BatteryLens -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

To create a signed direct-distribution archive, replace the team ID in `ExportOptions.plist` and run `scripts/archive.sh` with a Developer ID signing identity available in the keychain.

## Device sources

The app reads the Mac battery through IOPowerSources, compatible accessories through I/O Registry, generic Battery Service devices through CoreBluetooth, and paired iPhone/iPad data through the isolated helper protocol. The paired-device helper discovers compatible tooling at packaging time; a distribution build must bundle audited, signed tooling before enabling that source for release.

## Privacy

No account or external service is required. Nearcast is disabled by default; when enabled, secrets live in Keychain and snapshots are authenticated and encrypted before local-network transport. Diagnostic exports redact device names, levels, identifiers, peer secrets, and raw payloads.
