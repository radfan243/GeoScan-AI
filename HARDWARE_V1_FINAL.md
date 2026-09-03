# GeoScan-AI V1 — Hardware Baseline

> **Status:** LOCKED BASELINE / pre-assembly. This document fixes the electrical interfaces used by the current firmware. It is not a claim of 5–6 m detection performance.

## 1. ESP32 pin map (must match firmware)

| Function | ESP32 GPIO | Direction | Notes |
|---|---:|---|---|
| Sensor ADC input (temporary V1 interface) | GPIO34 | Input only | Current firmware reads `analogRead(GPIO34)`. Do not exceed ESP32 ADC input limits. |
| Buzzer | GPIO25 | Output | Active 5 V buzzer must be driven within its voltage/current limits; use a transistor driver if required by the selected buzzer. |
| Vibration motor control | GPIO26 | Output | **Do not connect motor directly to GPIO26.** Use a transistor/MOSFET driver and flyback diode. |
| I2C SDA (future ADS1115) | GPIO21 | I/O | Reserved for ADS1115. |
| I2C SCL (future ADS1115) | GPIO22 | Output | Reserved for ADS1115. |

## 2. Power and protection

```text
12 V BATTERY (+)
      |
    FUSE
      |
   SWITCH
      |
   +12 V BUS --------------------> coil driver power stage
      |
   BUCK CONVERTER
      |
    +5 V BUS --------------------> 5 V peripherals / buzzer as specified
      |
   ESP32 5 V/VIN input (board-dependent)

BATTERY (-) ----------------------> common GND
```

- Install the **fuse immediately after the battery positive terminal**.
- Use a fuse holder rated for the battery/system current.
- **Do not select the final fuse amperage by guesswork**; select it after measuring the assembled load and checking wire/current ratings.
- Keep the 12 V coil-current path physically separate from the low-level ADC signal path.
- Use a common ground, but route high-current return paths away from the LM358/ADC ground wiring.

## 3. Signal chain

```text
SEARCH COIL
    |
    v
COIL DRIVER / POWER SWITCH
    |
    +---- electromagnetic response
    |
    v
ANALOG FRONT END (LM358)
    |
    v
ADS1115 (I2C)
    |       \
   SDA      SCL
    |         |
 GPIO21     GPIO22
      \       /
        ESP32
          |
         BLE
          |
       Flutter app
```

### Important implementation state

The current firmware still reads the sensor from **GPIO34**, not from ADS1115. Therefore **do not wire ADS1115 into the signal path and assume the current firmware is already using it**. The firmware must be updated and tested before ADS1115 becomes the production ADC path.

## 4. MOSFET/driver rule

The current project previously listed IRLZ44N. Do **not** drive an IRLZ44N gate directly from an ESP32 GPIO as the final design. Use a gate-driver stage or a MOSFET whose RDS(on) is explicitly specified at a suitable 3.3 V gate voltage.

A final driver schematic must be selected together with the coil topology and measured current. Do not guess the gate resistor, pull-down, current-limit, or coil timing values.

## 5. Vibration protection

```text
ESP32 GPIO26 -> transistor/MOSFET driver -> vibration motor
                                      |
                               flyback diode
```

The motor must have its own suitable supply path. GPIO26 only controls the driver.

## 6. Buzzer

GPIO25 is the current firmware buzzer output. A buzzer that needs more current than an ESP32 GPIO can safely provide must use a transistor driver. Never use the GPIO as a high-current supply.

## 7. ADS1115 interface

When enabled in firmware:

- ADS1115 VDD: regulated supply within the module/IC operating range.
- GND: common system ground.
- SDA: GPIO21.
- SCL: GPIO22.
- Address: use the module's default address unless the firmware explicitly changes it.
- Analog input must remain within the ADS1115 input/common-mode and supply constraints.
- Add input protection/filtering appropriate to the actual analog front end.

## 8. Depth and target identification

The app may display **Estimated Depth** and **Confidence**, but these are estimates until the complete coil + analog front end + ADC system is calibrated against known targets and known burial depths.

The firmware must not fabricate a measured `5 m`, `6 m`, gold percentage, copper percentage, etc. from signal strength alone.

## 9. Purchase gate

Before purchasing the final electronics, confirm:

- [ ] Exact search-coil dimensions/turn count/wire diameter
- [ ] Coil-driver topology and measured current
- [ ] MOSFET or gate-driver part number
- [ ] LM358 gain/filter component values
- [ ] ADS1115 input scaling/protection
- [ ] Buck converter current rating
- [ ] Fuse rating based on measured/expected current
- [ ] Wire gauge for the 12 V/high-current path
- [ ] Buzzer voltage/current
- [ ] Vibration motor voltage/current

**Until these values are locked, this document is the safe wiring baseline but not a fabrication-ready schematic.**
