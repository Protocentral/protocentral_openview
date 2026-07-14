# OpenView 3 — Architecture

Orientation for anyone working on this codebase.

## What this is

OpenView 3 is a Flutter companion app for ProtoCentral biosignal/sensor
boards. It receives framed data over **USB/serial, BLE, or Wi-Fi (TCP)**,
decodes it into channel/matrix/event streams, visualizes it live, and records
to `.hpd` (BIOSIG v1) files for later replay. Package version is `3.0.0+131`.

Targets: Windows, macOS, Linux (USB/UART, BLE, Wi-Fi) and Android, iOS (BLE,
Wi-Fi). USB is desktop-only.

**Transport availability is gated by `BoardDescriptor.transports` per board:**
every board supports USB; **BLE** is Sensything OX/CAP + **HealthyPi 5**
(multi-characteristic GATT); **Wi-Fi** is Sensything + HealthyPi. Streaming BLE
uses `universal_ble` with tagged per-characteristic frames (`BleFrame`) so boards
like HealthyPi 5 (one signal per char) and Sensything (single stream char) share
one path.

## Commands

```bash
flutter pub get                    # install dependencies
flutter run -d macos               # run on desktop (or windows / linux)
flutter run -d <device-id>         # run on a connected mobile device
flutter analyze                    # static analysis / lint (uses flutter_lints)
flutter test                       # run all tests
flutter test test/widget_test.dart # run a single test file
flutter build macos                # release build (or windows / linux / apk / ios)
dart run flutter_launcher_icons    # regenerate platform launcher icons
```

There is currently only one test (`test/widget_test.dart`). Test coverage is
minimal — do not assume a test exists for a given unit.

## Architecture

Data flows in one direction through clearly separated layers. The key design
goal: **a board is declared, not coded**. Adding a board should not touch
transport, protocol, UI, or recording code.

```
Transport → Framer → Router → (Channel/Matrix/Event buffers) → UI
                                          ↓
                                      Recorder → .hpd file → Replay
```

### Layers (under `lib/`)

- **`transport/`** — `TransportService` is the common interface (scan, connect,
  `Stream<Uint8List> bytes`, `Stream<TransportEvent> events`, send). Three impls:
  `UsbSerialService` (flutter_libserialport, desktop), `BleService`
  (universal_ble — scans broadly then keeps only peripherals that resolve to
  a BLE-capable/Sensything descriptor via `BoardRegistry.matchBle`), and
  `WifiService` (raw TCP socket; manual host:port, no mDNS yet). Transports only
  move bytes; they know nothing about packets. `ConnectionController` hands each
  transport its link params from the descriptor before connecting
  (`setBaudRate` for USB, `setProfile` for BLE).

- **`protocol/`** — `PacketFramer` (`packet_framer_v3.dart`) is a byte-by-byte
  state machine that parses the ProtoCentral wire format
  `[0x0A][0xFA][LEN_LSB][LEN_MSB][PKT_TYPE][...PAYLOAD...][0x0B]` (the framer
  also tolerates a `0x00` pad before the `0x0B` EOF). It is parameterized by an
  allow-list of known packet types; unknown types are surfaced (not dropped) so
  the Console screen can hex-dump them. `PacketRouter` takes a `FramedPacket`,
  looks up the board's `PacketSpec.decode`, and fans the resulting
  `DecodedPacket` out to `onChannel` / `onMatrix` / `onEvent` / `onDecodedPacket`
  sinks.

- **`boards/`** — the declarative board registry. This is where most new work
  happens (see "Adding a board" below). Each `BoardDescriptor` bundles
  `ChannelSpec`s (1-D time series), `MatrixSpec`s (2-D frames, e.g. ToF depth
  maps), `PacketSpec`s (a `pktType` → pure decoder function), `CommandSpec`s
  (host→board byte sequences), and BLE/USB transport profiles. `BoardRegistry`
  (`board_registry.dart`) lists every descriptor and matches discovered USB
  ports by VID/PID/product-name.

- **`boards/descriptors/`** — one file per board (declarations).
  **`boards/decoders/`** — pure `Uint8List payload → DecodedPacket` functions.
  Decoders are side-effect-free and unit-testable in isolation. `shared_codecs.dart`
  has the little-endian int readers.

- **`data/`** — `ChannelBuffer` and `MatrixBuffer` ring buffers. Allocated at
  connect time in `ConnectionController` from the descriptor (channels sized to
  ~10 s at their sample rate, matrices to ~5 s of frames).

- **`controllers/`** — `ChangeNotifier`s exposed via `provider`. The graph is
  built once in `main.dart` and registered with `Provider.value` in `app.dart`:
  - `ConnectionController` — owns the active transport, framer, router, and all
    live buffers/counters. The hub everything reads from.
  - `ScanController` — device discovery across transports.
  - `RecordingController` — subscribes to the connection's decoded-packet
    stream and drives the `.hpd` writer.
  - `RecordingsBrowserController`, `ReplaySession`, `ChannelController`.

- **`recording/`** — `.hpd` (BIOSIG v1) block-based, append-only format.
  `BiosignalFileWriter` / `BiosignalFileReader` are lifted verbatim from
  `healthypi_studio` so files round-trip between the two apps — preserve binary
  compatibility (magic `BIOSIG`, 64 KB blocks, `DATA`/`EVNT`/`INDX` markers).

- **`ui/`** — `MaterialApp.router` with `go_router`. `AppRoutes` defines a
  `ShellRoute` wrapping all screens in `AdaptiveScaffold` (responsive
  desktop/mobile nav). Screens: home, scan, live, recordings, replay, console,
  settings. App is locked to dark theme.

- **`theme/`** — `AppTheme` plus spacing/shapes/signal-color tokens. Bundled
  fonts (Saira, Jost, Montserrat, JetBrainsMono) are declared in `pubspec.yaml`
  and referenced by family name from `AppTheme`.

### Adding a board

1. Write `lib/boards/descriptors/<board>.dart` exporting a `BoardDescriptor`
   (channels, matrices, packets pointing at decoder functions, commands,
   USB/BLE profile). `transports: TransportSupport(usb/ble/wifi)` declares which
   transports the board speaks — this alone gates the scan-screen board lists.
2. Write decoder function(s) in `lib/boards/decoders/<board>_decoders.dart`
   (pure `Uint8List → DecodedPacket`).
3. Register the descriptor in `BoardRegistry.all` in `board_registry.dart`.

No edits to transport, framer, router, controllers, UI, or recording code
should be needed. If you find yourself editing those layers to support a board,
reconsider — the abstraction is meant to absorb board differences.

## Platform notes

- **macOS shutdown**: `main.dart` intercepts window close via `window_manager`,
  finalizes any in-flight recording, shuts down USB/BLE/Wi-Fi, then hard-`exit(0)`
  to skip Flutter's macOS engine teardown (a known crash in the SkFontCache
  destructor). Don't "fix" this by letting the engine tear down normally.
- USB read worker must exit *before* the port FD is closed — see
  `UsbSerialService.shutdown`.
- **macOS entitlements/Info.plist**: BLE needs `com.apple.security.device.bluetooth`
  + `NSBluetoothAlwaysUsageDescription`; Wi-Fi (TCP client) needs
  `com.apple.security.network.client`. These are set in both `DebugProfile`/`Release`
  entitlements; the sandboxed release build silently blocks BLE/TCP without them.
- **BLE plugin — `universal_ble` only (replaces earlier `flutter_blue_plus`).**
  `universal_ble` (BSD-3) covers all platforms including web and is desktop-first.
  **Do not reintroduce `flutter_blue_plus`.** When merging or cherry-picking
  BLE/HealthyPi changes from older branches, re-express them on `universal_ble` —
  never take a `flutter_blue_plus` `BleService` wholesale.
  `BleService` (`lib/transport/ble_service.dart`) is the single streaming contact
  point; `SmpBleTransport` is the SMP contact point. Both use universal_ble's
  **static/singleton API keyed by `deviceId`** (not device objects) and hold
  resolved service/characteristic UUID strings. Keep the `TransportService` /
  `SmpTransport` abstractions (do not leak plugin types above those layers).
  universal_ble requires **iOS ≥ 13.1**, macOS ≥ 10.15, Android `minSdk 21`.
  Multi-characteristic boards (HealthyPi 5) emit tagged `BleFrame`s; single-char
  boards (Sensything) collapse via `BleProfile.resolvedStreams`. The **Developer
  tab** is a decoupled unfiltered GATT playground — also on `universal_ble`, never
  touches streaming `BleService`/`ConnectionController`.
- `pubspec.yaml` has `dependency_overrides` pinning `csv` and `intl` to older
  majors; respect these when adding deps that touch them.

## SMP / MCUmgr Device Manager + Developer BLE tool

A **generic SMP/MCUmgr device-management** feature lives at the top-level
**"Device Manager"** destination: scan → connect (its own BLE link) → OS/Image/FS
management for **any SMP-enabled device** (gated on the SMP service
`8d53dc1d-1db7-4cd3-868b-8a527460aa84`), plus a ProtoCentral-only HPI_HS Health
Store view. It is a **decoupled subsystem** — it does NOT go through the streaming
`ConnectionController`/framer (SMP is request/response over a separate GATT service).

**Core protocol package:** [`mcumgr_dart`](https://pub.dev/packages/mcumgr_dart)
(`^0.1.0` on pub.dev) — pure Dart `SmpMessage` / `SmpClient` / `SmpTransport` +
`OsMgmt` / `ImgMgmt` / `FsMgmt`. Do **not** vendor it as a path/submodule; depend
on the hosted package.

**App-side integration:**
- `lib/smp/smp_ble_transport.dart` — `universal_ble` transport; gates on the SMP
  service; notify + write-without-response; MTU refresh
- `lib/controllers/smp_controller.dart` — scan (+ system devices), connect,
  facades, console log, auto-reconnect, HELLO probe, MTU settle
- `lib/ui/screens/device_manager/` — UI split across part files:
  `device_manager_screen.dart` + scan/connected/device_info/firmware/files/
  health_store/console/shared_widgets
- `lib/mcumgr/hpi_hs.dart` + `lib/models/hs_*` — vendor Health Store (not in
  `mcumgr_dart`)

**Status:** OS echo hardware-verified; image `list` + `upload` verified on a Move;
full DFU install (upload → test → reset → confirm) is **WIP / advanced use only**
(UI-labelled as such). FS + HPI_HS built; pending broader hardware tests.

**Developer tab** stays in main nav for all users — unfiltered BLE GATT playground
(`developer_screen.dart` + `developer_ble_controller.dart`), intended as a
general-purpose BLE/MCUmgr bring-up tool. Separate from streaming Connect and from
Device Manager's SMP link.

**BLE MTU gotcha:** on macOS/iOS the ATT MTU is negotiated just *after* connect, so a
value read during `connect()` is the 23-byte default (`maxWriteLength` 20). `SmpController`
polls it for a few seconds post-connect (`_settleMtu`) and re-queries before uploads;
`ImgMgmt`/`FsMgmt` read `maxWriteLength` dynamically. Verified: settles 20 → 244 B on a
Move. If it stays 20, the firmware is capping the MTU (`CONFIG_BT_L2CAP_TX_MTU`).

- **Full spec:** `SMP_INTEGRATION_HANDOFF.md` (repo root) — some paths still describe
  the pre-extraction layout; prefer this section + the pub.dev package for the core.
- The `mcumgr_flutter` plugin was evaluated and rejected (native mobile-only; no
  desktop) — see handoff §2A.

## Reference

- `SMP_INTEGRATION_HANDOFF.md` — SMP/MCUmgr Device Manager integration spec.
- `README.md` — wire-format packet tables (Mermaid `packet-beta` diagrams) for
  HealthyPi packet types.
- `docs/protocols/tmf8829-wire-format.md` — TMF8829 dToF depth-frame format.
