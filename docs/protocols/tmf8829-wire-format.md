# TMF8829 dToF — OpenView 3 Wire Format

Firmware contract for boards built around the ams-OSRAM TMF8829 direct
Time-of-Flight ranging sensor. Implement this on the MCU and OpenView 3 will
render the depth heatmap automatically.

OpenView 3's decoder for this packet:
[`lib/boards/decoders/tmf8829_decoders.dart`](../../lib/boards/decoders/tmf8829_decoders.dart)
(function `decodeTmf8829Pkt6`).

Descriptor (channels / matrices / packet type / USB profile):
[`lib/boards/descriptors/tmf8829.dart`](../../lib/boards/descriptors/tmf8829.dart).

---

## Packet

One depth frame goes out as a single OpenView packet using the standard
ProtoCentral framing:

```
┌────┬────┬────────┬────────┬─────────┬───────────────────────────┬────┐
│SOF1│SOF2│ len_LSB│ len_MSB│ pktType │      PAYLOAD (len bytes)  │EOF │
│0x0A│0xFA│        │        │  0x06   │                           │0x0B│
└────┴────┴────────┴────────┴─────────┴───────────────────────────┴────┘
```

- `len` is the **payload length** — it does **not** include the SOF, length,
  pktType, or EOF bytes.
- Little-endian.
- Must be `> 0` and `<= 8192`. OpenView's framer caps payload length at 8192
  specifically to accommodate this format.

## Payload layout

All multi-byte fields little-endian.

| offset | size | field | notes |
|---:|---:|---|---|
| 0 | `u8` | `rows` | 1..64 (TMF8829 typical: 8..48) |
| 1 | `u8` | `cols` | 1..64 (TMF8829 typical: 8..32) |
| 2 | `u16[rows*cols]` | `pixels` | distance in **mm**, row-major. `0` = no return / invalid. |

```
payload_len = 2 + rows * cols * 2
```

### Examples

| grid | payload | packet (with framing) |
|---|---:|---:|
| 8×8 | 130 B | 136 B |
| 8×16 | 258 B | 264 B |
| 16×16 | 514 B | 520 B |
| 48×32 (max) | **3074 B** | **3080 B** |

### Pixel ordering

Row-major. `pixels[r * cols + c]` where `r ∈ [0, rows)`, `c ∈ [0, cols)`.
Row 0 is rendered at the **top** of OpenView's heatmap; column 0 is the
**left** edge.

### "No return"

A pixel value of `0` mm is treated as no-return. OpenView renders these as
black and excludes them from auto-scaling, so a few invalid pixels don't
collapse the visible range.

### Endianness

Little-endian everywhere. On a little-endian MCU (Cortex-M, ESP32, …) you
can `memcpy` a `uint16_t` array straight to the UART buffer without byte
swapping.

## Cadence

~10 Hz at full 48×32 is the recommended starter rate. OpenView's
`HeatmapView` caps repaints at 30 Hz, so higher frame rates don't render any
prettier — but they do increase USB bandwidth.

## Grid switching

`rows` and `cols` are read **per packet**. Firmware is free to change modes
at any time without coordinating with OpenView; the heatmap resizes on the
first packet at the new dimensions.

### Host-driven mode change

OpenView's Live screen exposes a **Mode** segmented button (8×8 / 16×16 /
32×32 / 48×32). Clicking a segment emits this packet **host → board**:

```
┌────┬────┬────────┬────────┬─────────┬──────┬──────┬────┐
│SOF1│SOF2│ len_LSB│ len_MSB│ pktType │ rows │ cols │EOF │
│0x0A│0xFA│  0x02  │  0x00  │  0x10   │      │      │0x0B│
└────┴────┴────────┴────────┴─────────┴──────┴──────┴────┘
```

- `pktType = 0x10` — "set TMF8829 grid mode".
- 2-byte payload: `rows` (uint8) and `cols` (uint8).
- Total wire size: **8 bytes**.

Concrete byte sequences (copy-pasteable into a logic-analyser / firmware
test harness):

| Mode | Hex |
|---|---|
| 8×8 | `0A FA 02 00 10 08 08 0B` |
| 16×16 | `0A FA 02 00 10 10 10 0B` |
| 32×32 | `0A FA 02 00 10 20 20 0B` |
| 48×32 | `0A FA 02 00 10 30 20 0B` |

Firmware is expected to:
1. Accept the packet.
2. Reconfigure the TMF8829 to the requested grid mode.
3. Continue emitting depth frames per the format above with the new
   `rows` and `cols`.

OpenView doesn't expect a reply. It just observes the resulting stream
and the heatmap auto-resizes on the first frame with new dimensions.
If the firmware can't honour the request (e.g. the sensor refused the
mode change), continue emitting frames at the current mode and OpenView
will simply keep showing the unchanged grid — no UI error path needed.

If firmware doesn't implement pktType 0x10 yet, OpenView's Mode button
still works locally (highlights the user's selection) but the board
keeps emitting whatever it was. Add the handler when you're ready.

### Sample firmware-side parser (C)

```c
/* Call this on every received byte from the OpenView host. */
void openview_on_byte(uint8_t b) {
    static enum { S_INIT, S_SOF1, S_LEN_LO, S_LEN_HI, S_TYPE, S_PAYLOAD, S_EOF } s = S_INIT;
    static uint16_t len = 0;
    static uint8_t  type = 0;
    static uint8_t  payload[16];
    static uint16_t pi = 0;

    switch (s) {
    case S_INIT:    if (b == 0x0A) s = S_SOF1;            return;
    case S_SOF1:    s = (b == 0xFA) ? S_LEN_LO : S_INIT;  return;
    case S_LEN_LO:  len = b;          s = S_LEN_HI;       return;
    case S_LEN_HI:  len |= (b << 8);  s = S_TYPE;
                    if (len > sizeof payload) { s = S_INIT; }
                    return;
    case S_TYPE:    type = b; pi = 0; s = (len == 0) ? S_EOF : S_PAYLOAD; return;
    case S_PAYLOAD: payload[pi++] = b; if (pi == len) s = S_EOF; return;
    case S_EOF:
        if (b == 0x0B) {
            if (type == 0x10 && len == 2) {
                /* Set TMF8829 grid mode. */
                tmf8829_set_grid(payload[0] /* rows */, payload[1] /* cols */);
            }
            /* future: more command pktTypes here */
        }
        s = S_INIT;
        return;
    }
}
```

## Sanity checks performed by OpenView

Frames that fail any of these are silently dropped (no UI error):

- `1 <= rows <= 64`
- `1 <= cols <= 64`
- `payload_len >= 2 + rows*cols*2`

Framer-level errors (wrong SOF, missing EOF, oversized length) are logged
on the **Console** tab with the first 16 bytes of each offending packet as
a hex dump. If frames look fine on the wire but OpenView shows nothing,
check the Console tab first — wrong-pktType drops are the most common
firmware error.

## Reference sender (C, no allocator)

```c
#include <stdint.h>
#include <stddef.h>

/*
 * Emits one dToF depth frame on the wire.
 *   rows, cols     dimensions of this frame
 *   pixels         row-major, length == rows*cols, distance in mm (0 = no return)
 *   write_bytes    your UART/USB send-blob primitive (blocking or buffered, your call)
 */
void openview_send_dtof_frame(uint8_t rows,
                              uint8_t cols,
                              const uint16_t *pixels,
                              void (*write_bytes)(const uint8_t *, size_t))
{
    const uint16_t payload_len = (uint16_t)(2 + (size_t)rows * cols * 2);

    /* Frame header */
    uint8_t header[5];
    header[0] = 0x0A;                          /* SOF1 */
    header[1] = 0xFA;                          /* SOF2 */
    header[2] = (uint8_t)(payload_len & 0xFF); /* len LSB */
    header[3] = (uint8_t)(payload_len >> 8);   /* len MSB */
    header[4] = 0x06;                          /* pktType — TMF8829 dToF */
    write_bytes(header, sizeof header);

    /* Payload header (rows, cols) */
    uint8_t dims[2] = { rows, cols };
    write_bytes(dims, sizeof dims);

    /* Payload body: pixels in little-endian.
       On a little-endian MCU you can send (uint8_t*)pixels directly. */
    write_bytes((const uint8_t *)pixels, (size_t)rows * cols * 2);

    /* Footer */
    uint8_t eof = 0x0B;
    write_bytes(&eof, 1);
}
```

For non-blocking transports, the same byte stream can be queued into a
single contiguous buffer of length `6 + payload_len` (header + payload +
EOF) and pushed in one shot — OpenView's framer does not require packet
boundaries to align with transport-level write boundaries.

## Transport defaults

- **USB-CDC** is the primary transport. OpenView's descriptor declares
  `921600` baud as the default; any baud that keeps up with
  `rows * cols * 2 * frame_rate` bytes/sec will do.
- At **48×32 × 10 Hz** that's about **30 KB/s** — comfortably under any
  modern serial link.

## Quick sanity test

A trivial 8×8 frame of all `1000` mm pixels:

```
0A FA 82 00 06         # SOF1 SOF2 len=130 (0x0082) pktType=0x06
08 08                  # rows=8, cols=8
E8 03 E8 03 ... ×64    # 64 × uint16 LE = 0x03E8 = 1000 mm
0B                     # EOF
```

If OpenView's heatmap fills with a uniform colormap value on this stream,
the framing is correct end-to-end.

## Related

- [Phase 4 in the rewrite plan (gitignored)](../../.v3-plan/06-phases.md) — heatmap board scope.
- [Phase 4 visualization design (gitignored)](../../.v3-plan/03-visualization.md) — the `HeatmapView` renderer this packet feeds into.
