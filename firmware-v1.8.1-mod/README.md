# Firmware snapshot — OpenMQTTGateway v1.8.1 (modified)

The complete set of OpenMQTTGateway **source files** used for this project,
based on stock v1.8.1 (commit `471348d`) with our three edits applied.
The two rtl_433_ESP library fixes live in `../patches/` (apply inside
`.pio/libdeps/esp32dev-rtl_433/rtl_433_ESP/`).

## Files changed vs stock v1.8.1

| File | Change |
|---|---|
| `environments.ini` | `esp32dev-rtl_433`: RTL_DEBUG=1, RTL_VERBOSE=35 (DSC), RAW_SIGNAL_DEBUG=true |
| `main/config_RF.h` | added `closed` → Contact entity (device_class `opening`) |
| `main/ZgatewayRTL_433.ino` | `closed` → binary_sensor (ON when open); MQTT dedup key includes `closed` state |

## Build

```bash
git clone --branch v1.8.1 https://github.com/1technophile/OpenMQTTGateway.git
# overlay these 3 files (same relative paths), then:
pio run -e esp32dev-rtl_433        # fetch libs
cd .pio/libdeps/esp32dev-rtl_433/rtl_433_ESP
patch -p1 < /path/to/0001-rtl433-esp-default-tolerance.patch
patch -p1 < /path/to/0002-rtl433-esp-trailing-gap.patch
cd - && pio run -e esp32dev-rtl_433
```

Flash: `pio run -e esp32dev-rtl_433 -t upload` (disconnect CC1101 from GPIO12 first — strapping pin).
