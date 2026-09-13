# BatteryLens Implementation Plan

## Outcome

Build BatteryLens as an independently implemented, local-first macOS utility that presents trustworthy battery status for the Mac and supported nearby devices. The first public release should meet every P0 requirement in the product specification while preserving a clean-room boundary from external source code and proprietary assets.

The recommended delivery strategy is a sequence of vertical slices. First prove the two riskiest device sources, then carry one internal-battery reading through the complete architecture, and only then add the remaining adapters and release surfaces.

## Scope and release boundaries

### Version 1.0

Version 1.0 includes the P0 scope:

- Native macOS app with configurable menu-bar and Dock presence
- Internal Mac battery
- Magic Mouse, Keyboard, and Trackpad where telemetry is exposed
- AirPods and Beats where telemetry is exposed
- Paired iPhone and iPad over USB through an isolated helper
- Device identity, reconciliation, freshness, hiding, and restoration
- Menu popover and settings
- Configurable low and full battery alerts, including snooze and deduplication
- Permission status, scanner diagnostics, reset controls, and local persistence
- Launch at login
- Signed and notarized direct distribution
- Accessibility, energy, privacy, recovery, and hardware validation required by the P0 release checklist

### Version 1.1

Defer the P1 scope until the P0 architecture and hardware matrix are stable:

- Generic BLE Battery Service devices
- Enhanced Bluetooth HID discovery
- Paired iPhone and iPad over Wi-Fi
- Supported cellular Apple-device BLE broadcasts
- Apple Watch relationships
- Per-device menu-bar pinning and Dock carousel
- All-device and single-device widgets
- Nearcast trusted LAN sharing and optional remote alert relay
- Signed automatic updates
- Redacted diagnostic export
- Simplified and Traditional Chinese localization

### Later releases

- Apple Pencil support
- Battery history and richer details
- Protocol and presentation enhancements

## Decisions required before feature implementation

Resolve these decisions in the first week and record each one as an architecture decision record.

| Decision | Recommended default | Exit evidence |
| --- | --- | --- |
| Product identity | Use BatteryLens internally; do naming and trademark review before public assets are finalized | Approved product name and asset brief |
| Minimum macOS version | Keep macOS 11 only if all required tools, dependencies, and UI paths pass a prototype; otherwise raise the minimum before UI work expands | Build and smoke test on the oldest supported OS |
| Persistence | Use a small SQLite repository behind a protocol; do not use SwiftData while macOS 11 remains in scope | Migration test and interrupted-write recovery test |
| Paired-device implementation | Select one auditable library/helper approach after license, redistribution, signing, USB, and timeout tests | Signed helper returns versioned JSON on the oldest and newest target OS |
| AirPods and Beats | Treat model and OS coverage as capability-based, not universal | Captured fixtures plus successful tests on representative hardware |
| Generic HID | Keep P1 and behind an Advanced toggle until OS reliability is demonstrated | Qualification results across the supported OS matrix |
| Nearcast transport | Prefer MultipeerConnectivity with an application-layer CryptoKit envelope | Threat model and two-Mac proof of concept |
| Data retention | Persist normalized state and redacted diagnostics only; never persist raw advertisements by default | Reviewed retention schema and deletion tests |

## Architecture baseline

Use an Xcode workspace with an app target, widget extension when P1 begins, helper target, and local Swift packages or framework targets with one-way dependencies.

```text
BatteryLensApp
  -> BatteryUI
  -> BatteryDiscovery
  -> BatteryAlerts
  -> BatteryPersistence
  -> BatteryPeers          P1

BatteryUI
  -> BatteryDomain

BatteryDiscovery
  -> BatteryDomain
  -> BatteryPersistence interfaces

BatteryAlerts
  -> BatteryDomain

BatteryPersistence
  -> BatteryDomain

BatteryWidget             P1
  -> versioned JSON snapshot only

PairedDeviceHelper
  -> versioned request and response JSON only
```

Enforce the following boundaries from the beginning:

- `DeviceResolver` is the sole owner of canonical device identity, aliases, reconciliation, and freshness transitions.
- `DeviceRepository` owns transactions and migrations; UI code never queries SQLite directly.
- Discovery adapters emit observations and health states. They never mutate UI or canonical device collections.
- `ScanScheduler` owns coalescing, cancellation, jitter, timeouts, backoff, and the one-scan-per-adapter rule.
- `AlertEngine` consumes resolved state transitions and a clock; it never initiates discovery.
- Presentation models receive immutable snapshots and perform sorting, grouping, labels, and capability-driven actions.
- The helper is invoked with an executable URL and argument array, bounded output, a deadline, and typed errors. No shell command strings enter product code.
- Widget and peer schemas are explicitly versioned and tested independently from the database schema.

## Delivery plan

Effort estimates assume one experienced macOS engineer, part-time product/design support, and access to the required physical devices. Calendar time will shorten with parallel engineering, but hardware qualification and release soak time remain sequential.

### Stage 0 Feasibility and clean-room setup

**Target:** 1 to 2 weeks

**Build**

- Create the repository, Xcode workspace, build configurations, bundle identifiers, entitlements, signing placeholders, and a minimal menu-bar app.
- Add a clean-room policy, dependency inventory, architecture decision record template, and source-provenance checklist.
- Define the representative hardware lab: Apple silicon laptop, Apple silicon desktop, Intel Mac if retained, Magic accessory, AirPods or Beats, and paired iPhone or iPad.
- Prototype internal battery access, AirPods or Beats observation, Magic accessory observation, and the paired-device helper.
- Establish a release build that signs the app and helper together.

**Gate**

- Internal battery works through supported APIs.
- AirPods or Beats and Magic telemetry are feasible on named hardware and OS versions, with unsupported cases reported as unavailable.
- A legally acceptable paired-device approach produces bounded, versioned JSON and survives cancellation and timeout.
- The oldest supported macOS version is fixed.
- No AGPL code, copied strings, copied assets, or mechanically translated implementation enters the repository.

If either high-risk P0 source fails this gate, revise the device-support promise or release priority before continuing.

### Stage 1 Foundation and executable contracts

**Target:** 2 weeks

**Build**

- Create `BatteryDomain` value types: device, observation, source identity, capabilities, health, power state, freshness, and alert state.
- Define `DiscoveryAdapter`, repository, clock, snapshot publisher, notification client, and helper-runner protocols.
- Implement `DeviceResolver`, `ScanScheduler`, and `DeviceRepository` as isolated components.
- Implement SQLite schema version 1 for devices, observations or diagnostic summaries, aliases, preferences, hidden state, alert state, and scanner health.
- Add structured, privacy-filtered logging and performance signposts.
- Add mock and fixture adapters that can model duplicates, missing fields, stale readings, failures, and cancellations.
- Create menu-bar, empty popover, settings shell, permission-status screen, and launch-at-login plumbing.
- Set up continuous integration for debug and release builds, unit tests, static analysis, and packaging smoke tests.

**Gate**

- The app launches without blocking the main thread.
- Mock devices survive relaunch and render in the popover.
- A second scan request coalesces with or cancels the first.
- Database writes are transactional and migration tests pass.
- Scanner failures are visible in diagnostics without exposing raw identifiers or payloads.

### Stage 2 First complete vertical slice

**Target:** 2 weeks

Carry the internal Mac battery through the entire system:

1. `MacPowerAdapter` emits a typed observation with timestamps and capabilities.
2. `ScanScheduler` responds to launch, interval, wake, power change, menu open, and manual refresh.
3. `DeviceResolver` produces a stable canonical device and freshness state.
4. `DeviceRepository` commits state and alert transitions atomically.
5. `AlertEngine` evaluates low and full threshold crossings using an injectable clock.
6. `SnapshotPublisher` writes a versioned atomic JSON snapshot, even though widgets remain P1.
7. The popover presents percentage, power state, freshness, source, and last update.
8. Settings alter behavior without relaunch.

**Gate**

- Cached popover content renders within the 150 ms p95 budget.
- Low, recovery, full, snooze, suppression, stale, and missing-value tests pass.
- Sleep and wake do not create duplicate scans or alerts.
- The feature works with AC power, battery power, charging, charged, optimized pause when exposed, and low-power mode.

### Stage 3 P0 device adapters

**Target:** 4 to 6 weeks

Add one adapter at a time to the proven contract.

#### Magic accessories

- Implement I/O Registry and Bluetooth observations using supported interfaces where possible.
- Define stable per-source identity and explicit cross-source aliases.
- Represent absent charging information as unavailable rather than inferred.

#### AirPods and Beats

- Parse only validated payload versions and lengths.
- Preserve left, right, and case components as explicit parent-child entities or component values according to the chosen domain model.
- Fail closed for unknown formats and retain only redacted diagnostic facts.
- Maintain binary fixtures for every qualified model and OS combination.

#### Paired iPhone and iPad over USB

- Run all third-party/device interaction inside the signed helper boundary.
- Define handshake, helper version, request ID, result schema, error taxonomy, maximum output, and deadline.
- Verify disconnect during query, locked device, untrusted pairing, malformed output, missing binary, incompatible version, and helper termination.

#### Cross-adapter reconciliation

- Test same-name/different-device, same-device/multiple-source, source handoff, conflicting levels, missing scan, relationship change, hide/unhide, and expiry.
- Add an explainability view showing chosen source, last update, competing observations where relevant, and scanner health.

**Gate for each adapter**

- Meets the scanner definition of done in the specification.
- Passes cancellation, timeout, permission, malformed-data, disconnected, energy, and real-hardware tests.
- Cannot remove healthy results from another adapter when it fails.

### Stage 4 Complete the P0 product experience

**Target:** 3 to 4 weeks

**Build**

- Finish first-run flow with contextual permission requests and per-source progress.
- Finish popover grouping, state icons and text, context menus, active-display positioning, keyboard behavior, and empty/error states.
- Implement static and internal-battery menu-bar icon modes.
- Complete hide/unhide, refresh, device details, and capability-driven actions.
- Complete global and per-device alert settings, thirty-minute snooze, notification actions, and permission recovery.
- Complete settings groups: General, Display, Discovery, Alerts, Nearcast placeholder, Privacy, and Advanced.
- Add granular reset operations with explicit confirmation and scope.
- Add VoiceOver labels, keyboard traversal, color-independent status, increased contrast, reduced motion, and pseudo-localization coverage.
- Add String Catalogs for all user-facing text.

**Gate**

- Every P0 user story has an automated or scripted acceptance test.
- Denying Bluetooth or notifications leaves unrelated features working.
- All visible actions are keyboard reachable.
- Forty-percent text expansion does not clip required UI.
- Stale readings are visibly qualified and never trigger threshold alerts.

### Stage 5 P0 hardening and release

**Target:** 3 to 4 weeks plus at least 1 week of soak

**Build and validate**

- Measure cold launch, popover latency, idle CPU, memory, wakeups, scan duration, and helper duration.
- Add adaptive scheduling for battery power, low-power mode, thermal pressure, sleep, and repeated failures.
- Test cache corruption and migration recovery without losing user preferences where possible.
- Exercise Bluetooth off/on/reset, connection churn, sleep/wake, multiple monitors, Dock positions, and missing values.
- Inspect network traffic to confirm the P0 build requires no external endpoint.
- Complete dependency licenses, checksums, notices, code-signing, hardened runtime, helper validation, notarization, and installation tests.
- Run the validation matrix on the oldest, intermediate, and current supported macOS releases.
- Produce a release candidate and run a real-device daily-driver soak.

**Version 1.0 release gate**

- All P0 requirement IDs and release-checklist rows have linked evidence.
- Popover latency, idle CPU, idle memory, crash-free, alert-correctness, and freshness targets pass or have an explicitly approved specification change.
- No open severity-one or severity-two defect remains.
- Privacy, licensing, signing, and notarization reviews are complete.
- Unsupported hardware and firmware combinations are documented accurately.

### Stage 6 P1 parity

**Target:** 8 to 12 weeks after 1.0

Deliver as independent vertical slices rather than one large parity release:

1. Generic BLE Battery Service and experimental HID adapters
2. Wi-Fi paired devices and supported cellular BLE observations
3. Parent-child relationships for Watch and other companion devices
4. Per-device menu-bar items and Dock carousel
5. Widget extension and selection intent using the versioned atomic snapshot
6. Nearcast trust enrollment, discovery, encrypted envelope, replay protection, revocation, and rotation
7. Signed automatic updates and redacted diagnostic export
8. P1 localization and a second full hardware and energy qualification

Nearcast should have its own threat model and release gate. Test secret mismatch, tampering, replay, expiry, sequence rollback, peer revocation, secret rotation, network changes, and protocol-version incompatibility before enabling remote data or alert relay.

## Test strategy

### Unit tests

- Identity and alias resolution
- Freshness and expiry transitions with a virtual clock
- Alert threshold crossing, recovery, snooze, duplicate suppression, and stale suppression
- Scheduler coalescing, cancellation, jitter bounds, timeout, and backoff
- Snapshot schema encoding and compatibility
- Redaction and retention rules
- Nearcast envelope validation and replay rejection in P1

### Adapter contract tests

Use captured, redacted fixtures and fake platform clients to test valid, partial, malformed, unknown-version, disconnected, denied, cancelled, and timed-out responses. Every adapter runs the same conformance suite in addition to source-specific tests.

### Integration tests

- Observation to canonical state to persistence to alert to UI snapshot
- Interrupted database write and migration
- Helper crash, hang, excessive output, malformed JSON, and version mismatch
- Multiple adapters reporting one physical device
- Permission changes while the app is running
- Sleep/wake and rapid connection events

### UI and accessibility tests

- Popover opening on the active display and predictable dismissal
- Full keyboard traversal and activation
- VoiceOver labels for device, percentage, state, source Mac, and freshness
- Light, dark, increased-contrast, reduced-motion, and long-string layouts
- Empty, scanning, partial, denied, stale, unavailable, and error states

### Performance and energy tests

Automate a thirty-minute idle benchmark and collect signposts for scan latency, popover rendering, persistence, helper work, widget publication, and peer traffic. Store benchmark results as release artifacts and compare them with a regression budget.

### Hardware qualification

Maintain a matrix keyed by macOS version, Mac architecture, device model, firmware, connection type, permission state, and expected fields. A scanner is not complete until it passes on representative physical hardware; simulator-only or fixture-only evidence is insufficient.

## Backlog structure and traceability

Use one epic per specification area and retain the requirement ID in every ticket, test name, and release-evidence record.

| Epic | Requirement groups |
| --- | --- |
| App lifecycle | APP 001 through APP 005 |
| Discovery and reconciliation | DEV 001 through DEV 007 plus sections 7 and 8 |
| Menu bar and Dock | UI 001 through UI 005 |
| Widgets | WID 001 through WID 005 |
| Alerts | ALT 001 through ALT 006 |
| Nearcast | NET 001 through NET 007 |
| Settings and diagnostics | SET 001 through SET 006 |
| Quality and release | NFR 001 through NFR 006 plus sections 10, 11, and 13 |

Each implementation ticket should contain:

- Requirement IDs and supported OS/device assumptions
- Observable user outcome
- Data and capability changes
- Permission and privacy behavior
- Cancellation, timeout, and failure behavior
- Unit, integration, UI, performance, and hardware evidence required
- Accessibility and localization checks
- Telemetry or diagnostic fields, with redaction rules

## Suggested first ten tickets

1. Establish repository, workspace, targets, CI, signing skeleton, and clean-room records.
2. Decide minimum macOS version and persistence library with build proofs.
3. Prove and license the paired-device helper; define its versioned JSON protocol.
4. Prove AirPods or Beats and Magic accessory observations on the target hardware matrix.
5. Implement domain models, capabilities, typed errors, clock, and adapter contract.
6. Implement SQLite repository version 1 and migration/recovery tests.
7. Implement scheduler and resolver with fixture-based concurrency and identity tests.
8. Implement the internal Mac battery vertical slice through popover, persistence, alerts, and snapshot.
9. Implement settings, permissions, scanner health, and launch-at-login foundations.
10. Establish automated latency and thirty-minute idle-energy benchmarks before adding more scanners.

## Delivery estimate

For one experienced macOS engineer with part-time QA/product support:

- Feasibility through P0 release candidate: approximately 14 to 20 engineering weeks
- Required release soak and hardware validation: at least 1 additional calendar week
- P1 parity: approximately 8 to 12 additional engineering weeks

The widest uncertainty is device telemetry, not the SwiftUI interface. The estimate should be revised after Stage 0 using measured adapter feasibility, supported OS decisions, helper licensing, and access to physical test hardware.
