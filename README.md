# ESP32 + CC1101 + OpenMQTTGateway: DSC WS4945 decode fix

Fix for DSC/Zicom **WS4945** (and EV-DW4927/WS4975) 433 MHz wireless door/window
contacts that are **received by the CC1101 but rejected by rtl_433_ESP** —
the classic "undecoded signal" symptom, especially with older/legacy sensor
revisions.

Tested on: ESP32-WROOM DevKit, CC1101 module, OpenMQTTGateway v1.8.1,
rtl_433_ESP v0.3.3, SmartRC-CC1101-Driver-Lib 2.5.7.

## Symptom

Triggering the sensor produces clean RF at 433.92 MHz (reliable 536 µs pulses /
1072 µs bit periods — textbook WS4945 RZ-OOK), yet MQTT shows:

```json
{"model":"undecoded signal","protocol":"signal parsing failed","duration":60231,"rssi":-77,"pulses":31}
```

Closed/restore events may decode while open events are silently rejected, and
Home Assistant never shows the contact's open/closed state.

## Root causes (3 independent bugs)

### 1. rtl_433_ESP dropped the default pulse tolerance  — *why nothing decoded*

Upstream rtl_433 `pulse_slicer.c` defaults to ±25% of the bit period when a
decoder doesn't set its own tolerance:

```c
if (s_tolerance <= 0)
    s_tolerance = s_long / 4; // default tolerance is +-25% of a bit period
```

The rtl_433_ESP vendored copy **deleted this line**. `dsc.c` sets no
`.tolerance`, so `s_tolerance` stayed **0** — any pulse deviating from exactly
536.000 µs (real-world jitter is ±25 µs) triggered `bitbuffer_clear` and the
WS4945 decoder never received a valid bit buffer. Decoders that set their own
tolerance (chuango, fineoffset, …) kept working, which is why the failure
looked sensor-specific.

**Patch:** `patches/0001-rtl433-esp-default-tolerance.patch`

### 2. Receiver never captures the trailing gap — *why open frames failed*

DSC is RZ-coded: a 1-bit is a carrier pulse, a 0-bit is **silence**. The ESP
interrupt receiver only writes a gap when the *next* pulse arrives, so the
trailing silence after the last pulse was recorded as gap 0. Frames whose
CRC/status ends in a 0-bit (typically **open** events) lost those final bits
and sliced to 47 bits — below the decoder's 48-bit gate. Closed frames (ending
in a 1-bit) decoded fine, which made open/close look like a state-dependent
mystery.

**Patch:** `patches/0002-rtl433-esp-trailing-gap.patch`

### 3. OpenMQTTGateway had no entity and swallowed state changes

- OMG's discovery table (`config_RF.h`) had **no `closed` entry** → Home
  Assistant never created an entity for the actual open/closed state (only
  battery/status/rssi/tamper), so the dashboard never seemed to change.
- OMG's MQTT dedup key was `id + temperature_C`; DSC has no temperature, so
  **open and close frames of the same sensor collided** — if you open→close
  within `time_avoid_duplicate` (3 s), the close frame was dropped as a
  "duplicate" and HA never saw the state flip.

**Patch:** `patches/0003-omg-closed-entity-and-dedup.patch`
(adds `closed` → binary_sensor `opening` class, ON when open; fixes dedup key)

## Applying

```bash
# 1. Fresh clone of OpenMQTTGateway v1.8.1
git clone --branch v1.8.1 https://github.com/1technophile/OpenMQTTGateway.git
cd OpenMQTTGateway

# 2. Apply the two rtl_433_ESP library patches after `pio run` fetches libs
#    (or apply inside .pio/libdeps/esp32dev-rtl_433/rtl_433_ESP/ manually)
pio run -e esp32dev-rtl_433   # fetches dependencies first
cd .pio/libdeps/esp32dev-rtl_433/rtl_433_ESP
patch -p1 < /path/to/0001-rtl433-esp-default-tolerance.patch
patch -p1 < /path/to/0002-rtl433-esp-trailing-gap.patch
cd ../../../../..

# 3. Apply the OpenMQTTGateway source patches
patch -p1 < /path/to/0003-omg-closed-entity-and-dedup.patch

# 4. Build & flash (disconnect CC1101 from GPIO12 before flashing — strapping pin)
pio run -e esp32dev-rtl_433
pio run -e esp32dev-rtl_433 -t upload --upload-port /dev/cu.usbserial-XXXX
```

Or run `./apply.sh` from a fresh v1.8.1 clone with the patches next to it.

## Verification

- `dsc_callback: row 0 bit count 48+` (was 47/never called)
- MQTT publishes both `"closed":0` (open) and `"closed":1` (closed) with
  `"mic":"CRC"`
- Home Assistant gains a `Contact` binary sensor per device (device_class
  `opening` — ON = open, OFF = closed, per HA docs convention)

See `evidence/capture-ws4945-open-close.log` for a working capture showing
`closed:0`/`closed:1` publishes from two different sensors.

## Notes

- The two lib patches are also in the upstream direction:
  - tolerance default = matches upstream `merbanan/rtl_433` `pulse_slicer.c`
  - trailing-gap = captures what SDR receivers naturally provide
- WS4945 packets are 48 bits; with reset-limit padding the slicer may produce
  55–56-bit rows — that is expected and upstream-blessed ("normal to get a 58
  bit packet").
- Hardware wiring used: SCK→GPIO18, MOSI→GPIO23, MISO→GPIO19, CSN→GPIO5,
  GDO0→GPIO12, GDO2→GPIO27, VCC→3V3, GND→GND. (GDO0 on GPIO12 is a strapping
  pin — disconnect CC1101 when flashing.)
- Some nearby DSC systems are unencrypted and in range: match decoded ESNs
  against the 6-hex-digit codes printed on your sensors to identify devices.
