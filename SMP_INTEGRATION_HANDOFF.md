# OpenView 3 — SMP / MCUmgr Device Management Integration (Handoff)

**Audience:** a developer working **inside the OpenView 3 repo**. This
document is self-contained — it captures
every decision, the source code to port, the OpenView 3 architecture, the
platform gotchas discovered during a prior investigation, and a phased plan.

**Goal:** Add a **generic SMP / MCUmgr device-management tool** to OpenView 3,
woven in as a **top-level "Device Manager" destination**. It must work with **any
SMP-enabled BLE device** (a Nordic dev kit running `smp_svr`, a HealthyPi Move,
etc.), not just ProtoCentral hardware. The standard OS/Image/FS management groups
are the generic tool; the custom **HPI_HS Health Store** group is ProtoCentral-
specific and only surfaces when detected.

---

## 0. Why this exists (the short version)

The functionality was first prototyped as a **standalone Flutter web app**
(`healthypi-move-webtool`, path below) that spoke **SMP/MCUmgr over Web
Bluetooth**. That prototype hit a hard wall: **Web Bluetooth on macOS/Windows/
Linux does not support on-demand BLE pairing/bonding** (only ChromeOS + Android
do — per the [Web Bluetooth implementation-status matrix](https://github.com/WebBluetoothCG/web-bluetooth/blob/main/implementation-status.md)).
The HealthyPi Move firmware **forces bonding on connect** (`bt_conn_set_security(conn, BT_SECURITY_L2)`
with passkey display), which desktop Web Bluetooth cannot complete → connect
fails with `NetworkError: Unsupported device`.

**OpenView 3 is a native Flutter app** (macOS/iOS/Android/Windows/Linux) using
`universal_ble`. Native CoreBluetooth/Android BLE **do** support
bonding/pairing normally (the OS shows the passkey dialog). So moving this
feature into OpenView **eliminates the entire Web Bluetooth limitation** and is
the correct long-term home. The prototype's protocol code is pure, portable Dart.

---

## 1. Locked decisions

| Decision | Choice |
|---|---|
| Target app | **OpenView 3** (`protocental_openview3`) — the new release |
| Reuse OpenView's streaming `ConnectionController`? | **No.** SMP is request/response over a *separate* GATT service; it must be a **decoupled subsystem** with its own connection. |
| Entry point / UX | **Top-level "Device Manager" destination** in the nav rail, with its own scan → connect → manage flow. |
| First capability to build | **Device Info (OS group)** + an **echo smoke test** (lowest-risk end-to-end proof), then Firmware DFU / Files / Health Store. |
| Generic vs ProtoCentral | OS/Image/FS + raw SMP console = generic (any device). **HPI_HS Health Store shows only when that custom group is detected.** |
| Capability gate | A device is "SMP-enabled" iff its GATT exposes the **SMP service `8d53dc1d-1db7-4cd3-868b-8a527460aa84`**. |
| BLE plugin | **`universal_ble` (BSD-3, maintained, all platforms incl. web) — adopted; spike passed, BLE streaming hardware-verified.** See §1B. |
| Protocol code base | **Reuse `healthypi_studio`'s hand-rolled SMP client core** + add a BLE transport (§2). Do **not** adopt the `mcumgr_flutter` plugin (native mobile-only; no macOS/Windows/Linux — see §2A). |

---

## 1B. BLE plugin — `universal_ble` (BSD-3), adopted

**Status: DONE.** The BLE layer is `universal_ble` (Navideck, **BSD-3**) — active,
maintained, and covering every target (Android, iOS, macOS, Windows, Linux, Web).
It has a complete API (`startScan`, `connect`, `discoverServices`,
`subscribeNotifications` + `characteristicValueStream`, `write` w/ & w/o response,
`requestMtu`, `getSystemDevices`) and an explicit `pair()`/`unpair()` API (relevant
to the bonded Move). BSD-3 keeps OpenView shippable as genuine open source with no
commercial-license or telemetry constraints.

The Phase-0 spike passed: `BleService` (`lib/transport/ble_service.dart`) runs on
`universal_ble` behind the unchanged `TransportService` interface, and **BLE
streaming is hardware-verified**. Build notes captured during adoption:
- **iOS deployment target must be ≥ 13.1** (`universal_ble` floor) — set in
  `ios/Podfile` + the Runner target. macOS ≥ 10.15, Android `minSdk 21`.
- `universal_ble` is a **static/singleton API keyed by `deviceId`** (not device
  objects) — hold device id + resolved service/characteristic UUID strings.

**Invariant:** write the SMP BLE transport (§5) directly on `universal_ble`, and keep
the SMP + transport layers plugin-agnostic (`TransportService` / `SmpTransport`) so
the BLE plugin stays swappable. Do not leak plugin types above `BleService` /
`SmpBleTransport`. The **Developer tab**
(`lib/controllers/developer_ble_controller.dart` +
`lib/ui/screens/developer_screen.dart`) is a decoupled, unfiltered BLE playground
(scan / connect / GATT read-write-notify) — reuse it as the reference for the SMP
transport's scan/connect/discover/notify calls.

---

## 2A. Prior art & build-vs-reuse — READ THIS FIRST

Do **not** reimplement SMP from scratch, and do **not** add the `mcumgr_flutter`
plugin. There are three candidate bases; the recommendation is #1.

**1. ✅ RECOMMENDED — `healthypi_studio`'s hand-rolled SMP client.**
`/Users/akw/Documents/GitHub/healthypi_studio/lib/services/smp_serial_client.dart`
is a **proven, in-production ProtoCentral MCUmgr/SMP client in pure Dart**. It:
- implements the SMP body (8-byte header + CBOR), **seq-matched request/response**,
  and RX **fragment reassembly**;
- has a **complete, working firmware-OTA `imageUpload()`** — SHA-256, device-driven
  offset chunking, progress callback, `os reset`, `rc` handling (image group 1 +
  os group 0). *This is the hard part, already done.*
- is already **transport-agnostic**: the identical SMP logic runs over **serial**
  (`flutter_libserialport`) **and TCP** (ESP32 WiFi passthrough) — "only the byte
  sink/source differs." Adding **BLE GATT** as a third transport is exactly the
  seam it was built for.
- is native and all-platform (pure Dart; no BLE-plugin coupling).

  **Caveat:** its outer framing is **serial `uart_mcumgr`** (`0x06 0x09` start /
  `0x04 0x14` continuation, base64, crc16-xmodem). **BLE does NOT use that.** BLE
  is raw GATT: write the SMP frame to the char, and reassemble notifications by
  the header's big-endian `len` (no base64, no crc16, no line framing). So:
  **extract the SMP-transaction core + mcumgr command builders from
  `smp_serial_client.dart`, and give it a BLE transport** that does
  length-prefixed notification reassembly (the web prototype's `SmpClient`
  already shows that reassembly cleanly — use it as the BLE-side reference).

**2. Web prototype (`healthypi-move-webtool`).** Cleaner separation
(`SmpTransport` abstraction, per-group files, HPI_HS models) and its `SmpClient`
already does **BLE-style length-prefixed reassembly** — but its transport targets
Web Bluetooth and its groups are less complete than Studio's OTA.
**Use it as the structural/BLE-reassembly reference and for the HPI_HS models;
take the battle-tested OTA/image logic from Studio.**

**3. ❌ `mcumgr_flutter` plugin — do not adopt.** See §2A-eval below.

### §2A-eval — why NOT the `mcumgr_flutter` plugin
- It is a **native iOS + Android only** wrapper (over Apple's
  iOS-nRF-Connect-Device-Manager and the Android mcumgr Java lib). It has **no
  macOS / Windows / Linux / web** implementation → throws / unavailable on
  desktop.
- OpenView 3 targets **desktop (macOS/Windows/Linux) as first-class** — and
  desktop macOS is the *entire reason* this work moved out of the web prototype.
  `mcumgr_flutter` **cannot cover the desktop targets**, so it would force a
  second, mobile-only code path alongside a desktop one.
- **No app in this org actually uses it.** (`move_ultralight_flutter` uses a
  *custom* DFU service `0x FF30`, not stock MCUmgr; `healthypi_studio` uses the
  hand-rolled Dart client above.) So there's no existing `mcumgr_flutter`
  integration to inherit.
- A single portable Dart SMP client (option 1) covers **every** OpenView target
  with one code path and reuses proven org code. That wins decisively.

  *It remains a useful **reference** for stock OS/Image/FS group ids, command ids,
  and CBOR key shapes — read its Dart source if a wire detail is unclear — but
  don't depend on it.*

---

## 2. Protocol source files (reference + port)

The web prototype has the cleanest **per-group** protocol layer and the HPI_HS
models; Studio has the proven OTA. Pull from both per §2A. **Read these before
writing anything.**

**Prototype repo:** `/Users/akw/Documents/GitHub/healthypi-move-webtool`
**Studio SMP client:** `/Users/akw/Documents/GitHub/healthypi_studio/lib/services/smp_serial_client.dart`

Port these files (pure Dart, no UI/plugin coupling — copy nearly verbatim):

| Prototype file | Ports to (suggested) | Notes |
|---|---|---|
| `lib/smp/smp_message.dart` | `lib/smp/smp_message.dart` | SMP header (8-byte) + CBOR codec. Depends only on `package:cbor`. |
| `lib/smp/smp_client.dart` | `lib/smp/smp_client.dart` | seq allocation, request/response matching, **fragment reassembly**, timeout. |
| `lib/smp/smp_transport.dart` | `lib/smp/smp_transport.dart` | Abstract transport interface + `SmpConnectionState` + `SmpException`/`SmpTransportException`. |
| `lib/mcumgr/os_mgmt.dart` | `lib/mcumgr/os_mgmt.dart` | **Phase 1.** echo/params/taskstat/datetime/reset. |
| `lib/mcumgr/img_mgmt.dart` | `lib/mcumgr/img_mgmt.dart` | Phase 3 (DFU). Partial in prototype. |
| `lib/mcumgr/fs_mgmt.dart` | `lib/mcumgr/fs_mgmt.dart` | Phase 4 (files). |
| `lib/mcumgr/hpi_hs.dart` | `lib/mcumgr/hpi_hs.dart` | Phase 5 (Health Store, ProtoCentral-only). |
| `lib/models/hs_sample.dart`, `lib/models/hs_type.dart` | `lib/models/…` | HPI_HS decoders (18-byte LE sample stride; type registry). |
| `docs/HPI_HS_API.md` | `docs/HPI_HS_API.md` | The custom-group contract. Copy for reference. |
| `ARCHITECTURE.md` | — | Read for the SMP wire-format details. |

**Do NOT port:** `lib/smp/smp_web_bluetooth_transport.dart` (Web-Bluetooth
specific), the prototype's `lib/ui/*`, `lib/services/device_service.dart`,
`web/`, or `macos/`. You will rewrite the transport (§5) and controller (§6) to
fit OpenView, and rebuild the screens in OpenView's theme.

**`cbor` dependency:** the prototype uses `cbor: ^6.x`. Add `cbor` to OpenView's
`pubspec.yaml` if not already present (`grep cbor pubspec.yaml`).

---

## 3. SMP protocol reference (so you don't need the prototype open)

**Transport (Nordic SMP GATT service):**
- Service UUID: `8D53DC1D-1DB7-4CD3-868B-8A527460AA84`
- Characteristic UUID: `DA2E7828-FBCE-4E01-AE9E-261174997C48` (write-without-response + notify; used both directions)

**SMP frame = 8-byte header + CBOR map payload:**
```
 offset field size notes
   0    op     1   0=read-req 1=read-rsp 2=write-req 3=write-rsp
   1    flags  1   0
   2    len    2   payload length, BIG-endian u16
   4    group  2   management group id, BIG-endian u16
   6    seq    1   request sequence; response echoes it
   7    id     1   command id within the group
```
- Response `op` = request `op` | 1; response echoes `seq`.
- **A single SMP response can span multiple BLE notifications** — reassemble by
  reading header `len` and buffering until `8 + len` bytes arrive, then match
  `seq` to the pending request. (`SmpClient` already does this.)
- Errors come back as SMP v1 `{"rc": <int>}` **or** SMP v2 `{"err":{"group","rc"}}`
  — handle both. (Prototype currently only surfaces `rc`; add `err` handling.)
- Chunk uploads to **ATT MTU − 3** bytes.

**Group ids:** OS = `0`, Image = `1`, FS = `8`, **HPI_HS = `0x1000`** (vendor range ≥ 64).

**OS group (Phase 1) command ids:** echo=0, taskstat=2, mpstat=3, datetime=4,
reset=5, mcumgr-params=6. Echo request payload `{"d":"..."}` → response `{"r":"..."}`.

---

## 4. OpenView 3 architecture (mapped) — where things plug in

OpenView uses **`provider`** for state and **`go_router`** for navigation.

**Providers are wired manually and passed down**, not created inline:
- `lib/main.dart` builds the controller graph (`UsbSerialService`, `BleService`,
  `WifiService`, `ConnectionController`, `ScanController`, `RecordingController`,
  `RecordingsBrowserController`, `SettingsController`) and passes them to
  `OpenViewApp`. **Add your `SmpController` here.**
- `lib/app.dart` registers them via `ChangeNotifierProvider<T>.value(value: …)`
  inside a `MultiProvider`. **Register `SmpController` here.** It also intercepts
  window close in `main.dart`'s `_CloseHandler` — add SMP disconnect/teardown
  there too.

**Navigation:**
- `lib/ui/app_routes.dart` — `AppRoutes` holds route constants + a `GoRouter`
  with a single `ShellRoute` wrapping all screens in `AdaptiveScaffold`.
  **Add `static const deviceManager = '/device-manager';` and a `GoRoute`.**
- `lib/ui/adaptive_scaffold.dart` — the nav rail / bottom bar. The
  `_destinations` list drives it, and `_selectedIndex()` maps a location to an
  index. **Add a `_NavDest(AppRoutes.deviceManager, 'Device Manager', Icons.dns_outlined, Icons.dns)`
  and a matching `location.startsWith('/device-manager')` case.** (Mind the
  index math in `_selectedIndex`.)

**Transport model (why we bypass it):**
- `lib/transport/transport_service.dart` — abstract `TransportService`
  (`bytes` stream in, `send()` out, `scan`/`connect`/`disconnect`) with
  `TransportKind {ble, usb, wifi}`, `TransportStatus`, `TransportTarget`.
- `lib/transport/ble_service.dart` — the **canonical example of the `universal_ble`
  API** for scan/connect/notify/write. **Read it and
  mirror its idioms** (see §5). It is **stream-oriented** (one notify
  characteristic → byte stream), which is the wrong shape for SMP's
  request/response, so SMP gets its own transport rather than extending this.
- `lib/controllers/connection_controller.dart` — orchestrates streaming
  (framer→router→channel buffers). **Not used by SMP.**
- BLE in OpenView is currently **Sensything-only** and filtered by
  `BoardRegistry.matchBle`. The `healthypi` descriptor is **USB/WiFi only** and
  is "HealthyPi 5" (not the Move). **SMP capability is independent of
  `BoardRegistry`** — do not add SMP devices to the registry; discover them by
  the SMP service UUID at connect time.

**Theme:** use `lib/theme/app_spacing.dart` (`AppSpacing.xs/sm/md/lg/xl`),
`Theme.of(context).colorScheme`, `Card`, `FilledButton`, etc. Match `home_screen.dart`
and `scan_screen.dart` visual patterns (cards, `_CardHeader`, hero, stat rows).

---

## 5. The SMP BLE transport (target: `universal_ble`)

Create `lib/smp/smp_ble_transport.dart` implementing the ported abstract
`SmpTransport`, on top of **`universal_ble`**. It is a **static/singleton** API
keyed by device id — hold `deviceId` + resolved service/characteristic UUID strings
(not device objects). `BleService` and the **Developer controller**
(`lib/controllers/developer_ble_controller.dart`) already exercise every call below
against real hardware — copy their idioms. Capability checklist (universal_ble 2.x):

- **Scan:** `UniversalBle.startScan()` + listen `UniversalBle.scanStream`
  (`Stream<BleDevice>`). `startScan` has **no timeout** — bound it yourself. Scan
  **broadly** (no service filter) — the SMP service is not advertised (gotcha §5.3).
  On web you MUST pass `withServices` (the SMP service) for post-connect access.
- **Connect:** `UniversalBle.connect(deviceId, timeout: …)`.
- **Discover:** `UniversalBle.discoverServices(deviceId)` → `List<BleService>`; locate
  the SMP service `8d53dc1d…` + characteristic `da2e7828…`. Compare UUIDs on the
  suffix (short 16-bit vs full 128-bit forms) — reuse ble_service's `_sameUuid`.
- **Notifications:** `UniversalBle.subscribeNotifications(deviceId, service, char)`,
  then listen `UniversalBle.characteristicValueStream(deviceId, char)` and feed raw
  bytes into `SmpClient` for reassembly.
- **Write:** `UniversalBle.write(deviceId, service, char, frame, withoutResponse: true)`
  (SMP char is write-without-response).
- **Pairing (Move):** handled by the OS on native connect (encrypted-char access);
  `UniversalBle.pair(deviceId)` if you need to force it. See gotcha §5.4.
- **Already-connected devices (macOS bonded):**
  `UniversalBle.getSystemDevices(withServices: […])` (gotcha §5.2). Note: this
  returns only devices **currently connected at the OS level**, not merely bonded.
- **MTU:** `UniversalBle.requestMtu(deviceId, 247)` where supported; derive
  `maxWriteLength = mtu − 3` (best-effort / OS-managed on some platforms — guard it).

### CRITICAL gotchas discovered — these are OS/CoreBluetooth-level and apply to ANY plugin

1. **The connection-state stream may replay its current value on subscribe.**
   If you subscribe to `UniversalBle.connectionStream(deviceId)` **before**
   connecting, you can get an immediate spurious `disconnected` that tears the
   connection down mid-flight. **Subscribe only AFTER connect succeeds, or ignore
   the first replayed event.** (`BleService` + the Developer controller both do the
   former.)

2. **macOS scan does not return already-connected/bonded peripherals.**
   CoreBluetooth omits connected devices from `scanForPeripherals`. A device the
   OS has auto-connected (because it's bonded) will **never appear in a scan** —
   the scan returns zero results. You must ALSO query already-connected system
   devices: `UniversalBle.getSystemDevices(withServices: […])`. Query with the
   services the device exposes (SMP `8d53dc1d…`, plus common `180D`/`180F` if
   relevant), match, and connect directly (no scan). **Merge scan results + system
   devices** in the picker. (`getSystemDevices` is unsupported on Web — scan-only
   there.)

3. **Generic SMP discovery:** most devices do **not advertise** the 128-bit SMP
   service UUID (advertising packet is only 31 bytes). So you **cannot** filter
   the scan by the SMP service. Scan **broadly** (no service filter), list all
   named devices (+ system devices), let the user pick, then **verify the SMP
   service exists via `discoverServices()` after connecting**. If absent → show
   "not an SMP-enabled device" and disconnect.

4. **Bonded devices & pairing on native:** the HealthyPi Move firmware forces
   `bt_conn_set_security(conn, BT_SECURITY_L2)` on connect (see the firmware repo
   `app/src/ble_module.c`), triggering passkey pairing. On native macOS/Android
   this is handled by the OS (system pairing dialog) — **this is expected and
   fine**, and is the whole reason native OpenView works where Web Bluetooth
   didn't. No app code needed beyond connecting.

5. **MTU settles *after* connect on macOS/iOS — don't cache it at connect.**
   CoreBluetooth runs the ATT MTU exchange just after the connection is up, so
   `requestMtu` read inside `connect()` returns the **23-byte default** (→
   `maxWriteLength` 20). This makes firmware DFU impossible (an SMP upload frame
   can't fit). Fix (implemented): poll `requestMtu` for a few seconds post-connect
   (`SmpController._settleMtu`) and re-query right before an upload; `ImgMgmt`
   reads `maxWriteLength` **dynamically** so the chunk size tracks it. Verified on
   a Move: `max write` rises from 20 → **244 B** (MTU 247) once settled. If it
   *stays* 20, that's a **firmware** cap — raise `CONFIG_BT_L2CAP_TX_MTU` (+ ACL
   buffer sizes) on the device; the app can't change it on macOS.

---

## 6. `SmpController` (mirrors the prototype's `DeviceService`)

Create `lib/controllers/smp_controller.dart` — a `ChangeNotifier` that owns the
SMP subsystem. Model it on the prototype's `lib/services/device_service.dart`:

- Holds the active `SmpTransport` + `SmpClient`, and the group facades
  (`OsMgmt os`, later `ImgMgmt img`, `FsMgmt fs`, `HpiHs hs`) — non-null only
  while connected.
- `Future<List<SmpScanTarget>> scan()` — broad BLE scan + `systemDevices`,
  returns pickable devices (name + id + rssi).
- `Future<void> connect(deviceId)` — connect, discover services, **assert SMP
  service present** (gate), wire notify/write into `SmpClient`, expose `os`.
  Also probe HPI_HS presence (attempt `hs.hello()`; success → reveal the Health
  Store screen; failure/`rc` → hide it).
- `disconnect()`, connection-state stream, and a **raw SMP console log**
  (mirror every request/response — the prototype's `SmpClient` takes a
  `log` sink; wire it to a bounded `List<ConsoleEntry>` like
  `ConnectionController.console`).
- Register in `main.dart` graph + `app.dart` MultiProvider + `_CloseHandler`.

---

## 7. Screens (Phase 1: Device Manager + Device Info)

Under `lib/ui/screens/device_manager/`:

- **`device_manager_screen.dart`** — the top-level destination. When
  disconnected: a **Scan** button + device list (name, id, RSSI, a chip if the
  SMP service is confirmed after connect). When connected: show device identity
  + tabs/sections for **Device Info** and **Console** (later: Firmware, Files,
  Health Store — each shown only when its group is available).
- **Device Info panel** — port the prototype's `lib/ui/device_info_screen.dart`
  layout (SectionCards): **Echo (smoke test)**, MCUmgr params, Task stats,
  Datetime get/set, Reset (with confirm). Wire each button to `svc.os!.…` and
  show results inline / in the console. (The prototype has echo already wired as
  a reference: `_echo(context)` calling `svc.os!.echo('hello move')`.)
- **SMP Console** — a raw request/response log view (reuse OpenView's
  `console_screen.dart` styling), fed by `SmpController`'s log.

**Phase-1 definition of done:** open Device Manager → Scan → pick the device →
Connect (native pairing completes if required) → Device Info → **Send echo** →
the same string round-trips and appears in the console. That proves transport +
framing + CBOR + fragment reassembly end-to-end against real hardware.

---

## 8. Phased plan

- **Phase 0 — `universal_ble` adoption + BLE spike. ✅ DONE.** `universal_ble`
  (BSD-3) added to `pubspec.yaml`; OpenView's `BleService` runs on it behind the
  **unchanged `TransportService` interface** (`scan`/`connect`/`bytes`/`send`); iOS
  deployment target bumped to 13.1; migration complete across all native platforms.
  BLE streaming (scan → connect → notify → write) is **hardware-verified**, and a
  Move connects + pairs + discovers services on macOS via the **Developer tab**.
- **Phase 1 — Device Info (OS group) + smoke test. ✅ DONE — echo hardware-verified.**
  Ported `lib/smp/` (`smp_message` w/ v1 `rc` + v2 `err`, `smp_client` reassembly,
  `smp_transport`), `lib/mcumgr/os_mgmt.dart`, `lib/smp/smp_ble_transport.dart`
  (universal_ble; gates on the SMP service), `lib/controllers/smp_controller.dart`,
  and `lib/ui/screens/device_manager/device_manager_screen.dart` (scan → connect →
  Device Info: echo/params/taskstat/datetime/reset + SMP console). Wired as the
  **Device Manager** nav destination. `cbor` added. **Echo round-trips on a real
  Move (`r:"…"` returns correctly)** → BLE transport + SMP framing + CBOR +
  fragment reassembly + seq matching all proven end-to-end.
- **Phase 2 — Generic polish. ✅ DONE.** SMP v1 `rc` **and** v2 `err` handling
  (`SmpMessage.rc`/`errorLabel`, named codes); friendly "not an SMP device" gate
  (`SmpBleTransport` throws → screen shows it); system-device merge (`getSystemDevices`);
  **console export** (SMP console → `.log` via `file_selector`); **robust auto-reconnect**
  — `SmpController` remembers the last device and, on an *unexpected* drop (link lost /
  device reboot after `os reset` / DFU), tears down the dead transport and retries the
  same device up to 3× with backoff (a *user* disconnect sets `_intentionalDisconnect`
  and skips it). Device Manager shows a "Reconnecting…" view with Cancel.
- **Phase 3 — Firmware DFU (Image group). 🔨 BUILT — partially hardware-tested.**
  `lib/mcumgr/img_mgmt.dart`: `list()` (parses image slots), `upload()` (SHA-256,
  device-driven offset loop ported from Studio's `imageUpload()`, **BLE-aware chunk
  sizing** from the transport's `maxWriteLength` so each request fits one write),
  `test()`/`confirm()`/`erase()`. `SmpController` gains an `img` facade; the Device
  Manager screen gains a **Firmware tab** (image list, file pick via `file_selector`,
  upload progress bar, Test & Reset, Confirm running, Erase). `crypto` added; macOS
  user-selected-files entitlement already present. Analyze + macOS build pass.
  **Hardware status: `list()` (read images) VERIFIED; `upload()` throughput VERIFIED
  (~12–13 kB/s at 216 B chunks once MTU settles to 244 B — see §5.5). Full DFU
  install (upload → test → reset → confirm boot) is a DEFERRED test** — when run,
  likely blocked on the Move's `Failed to open flash area ID 1` (secondary slot)
  firmware issue, not the app.
- **Phase 4 — File transfer (FS group). 🔨 BUILT — pending hardware test.**
  `lib/mcumgr/fs_mgmt.dart`: `stat()` (file size), `download()` + `upload()`
  (offset-loop chunking, BLE-aware). NOTE: **stock Zephyr fs_mgmt has NO directory
  listing and NO delete** — only file transfer + stat by absolute path — so this is
  a file-transfer panel (enter a `/lfs/...` path), not a browser. `SmpController`
  gains an `fs` facade; Device Manager gets a **Files tab** (stat / download-to-disk
  / upload-from-disk with progress).
- **Phase 5 — HPI_HS Health Store (ProtoCentral-only). 🔨 BUILT — pending hardware
  test.** Ported `lib/models/hs_type.dart` + `lib/models/hs_sample.dart` (18-byte LE
  stride, `<IqBBi`) and `lib/mcumgr/hpi_hs.dart` (group `0x1000`: HELLO / TYPES /
  SYNC + `syncAll` / SUMMARY / ACK / RECORDS list+get). `SmpController` gains an `hs`
  facade and **probes HELLO on connect** — the **Health Store tab appears only when
  HELLO succeeds** (non-HPI SMP devices reject the vendor group, so it stays hidden).
  The tab shows the HELLO handshake, fetches + displays the TYPES registry, `syncAll`
  → resolves samples against the registry (real value + unit + quality) → CSV export,
  SUMMARY (typed dashboard cards via `hs_summary.dart`), ACK, and the **RECORDS tier**
  (`Records` → `recordsList` → per-session download via `HpiHs.downloadRecord`
  chunked-`get` loop + **CRC-32 verify** (`utils/crc32.dart`) → `HsRecordSamples`
  decode (bytes-per-sample inferred from the header) → **fl_chart** multi-channel
  viewer with Save-raw + ACK). Wire-detail caveats (all handled defensively): SUMMARY
  keys, RECORDS header/`get` field names, record sample encoding — confirm against
  real Move responses. See the Move's `docs/HPI_HS_API.md`.

---

## 9. Build / test

```bash
# from protocental_openview3/
flutter pub get
flutter analyze lib/
flutter run -d macos          # native — bonding/pairing works here
```
- Native macOS Bluetooth needs the entitlement + usage string. OpenView already
  ships BLE, so `macos/Runner/*.entitlements` should already have
  `com.apple.security.device.bluetooth` and `Info.plist` an
  `NSBluetoothAlwaysUsageDescription` — **verify** (grep them); add if missing.
- **Work on a feature branch** (`git checkout -b feat/smp-device-manager`); this
  is a release app.
- If a bonded HealthyPi Move won't appear when scanning, that's gotcha §5.2 —
  use `systemDevices`. Confirm services via `discoverServices()` post-connect.

---

## 10. Reference index

- **Studio SMP client (RECOMMENDED base — proven OTA, multi-transport):**
  `/Users/akw/Documents/GitHub/healthypi_studio/lib/services/smp_serial_client.dart`
  (SMP body + CBOR + seq matching + `imageUpload()` OTA; serial + TCP transports —
  pure Dart, no BLE-plugin coupling). Also `lib/screens/firmware_update_screen.dart`
  for the OTA UI flow.
- Prototype (cleanest per-group layer, BLE reassembly, HPI_HS models, protocol docs):
  `/Users/akw/Documents/GitHub/healthypi-move-webtool`
  (`ARCHITECTURE.md`, `docs/HPI_HS_API.md`, `lib/smp/`, `lib/mcumgr/`, `lib/models/`).
- `mcumgr_flutter` plugin — reference only (native iOS/Android; not a dependency): https://pub.dev/packages/mcumgr_flutter
- `universal_ble` (the BLE layer — BSD-3, all platforms): https://pub.dev/packages/universal_ble · https://github.com/Navideck/universal_ble
- Move firmware (why bonding is forced): `/Users/akw/Documents/GitHub/move-fw-next-workspc/healthypi-move-fw-next`
  (`app/src/ble_module.c` → `bt_conn_set_security(conn, BT_SECURITY_L2)`, passkey
  pairing; `app/prj.conf` → `CONFIG_BT_BONDABLE=y`, no SMP-char encryption perms).
- OpenView seams (this repo): `lib/main.dart`, `lib/app.dart`,
  `lib/ui/app_routes.dart`, `lib/ui/adaptive_scaffold.dart`,
  `lib/transport/ble_service.dart` (`universal_ble` API exemplar),
  `lib/controllers/developer_ble_controller.dart` (unfiltered BLE scan/connect/GATT),
  `lib/transport/transport_service.dart`, `lib/theme/app_spacing.dart`.
- Web Bluetooth pairing limitation (context for why native): https://github.com/WebBluetoothCG/web-bluetooth/blob/main/implementation-status.md

---

*Prepared from a prototype-integration investigation. Everything above was
verified against the actual repos on this machine at handoff time; still re-check
file paths/line numbers before editing, as they drift.*
