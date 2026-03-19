# UGREEN DXP4800+ Thermal Fix for Unraid

The DXP4800+ thermal throttles under sustained load due to two compounding issues: factory thermal paste with poor die coverage (~40%), and ACPI firmware that controls fans based on board temperature instead of CPU temperature.

With proper repasting and BIOS SmartFan tuning, the DXP4800+ runs turbo boost permanently under sustained all-core load with no throttling. P-core holds 3.65 GHz at 85°C (was 100°C throttled to 2.2 GHz stock).

## The Problem

The UGREEN DXP4800+ (Intel Pentium Gold 8505) hits 100°C and thermal throttles during moderate sustained work — Roon library indexing, folder caching scans, anything that holds a core at 100% for more than a few seconds.

Two root causes:

1. **Factory thermal paste is terrible.** Only ~40% of the bare die was covered, with two small contact patches visible on the heatsink. The Pentium Gold 8505 has no IHS (integrated heat spreader) — it's a bare die making direct contact with the heatsink, so paste coverage is critical.

2. **ACPI fan binding is wrong.** All five fan cooling devices are bound to the board temperature sensor (`acpitz` / `thermal_zone0`), not the CPU sensor (`coretemp`). The board reads ~28°C regardless of CPU load, so the firmware never tells the fans to spin up.

## Diagnosis

### CPU vs. board temperature

`sensors` output under load:

```
coretemp-isa-0000
CPU Temp:     +100.0°C  (high = +100.0°C, crit = +100.0°C)  ALARM (CRIT)
Core 0:       +100.0°C
Core 8:        +82.0°C

acpitz-acpi-0
temp1:         +27.8°C
```

CPU at 100°C. Board at 28°C. Fans idle.

### ACPI thermal zone binding

Five Fan cooling devices bound to `thermal_zone0` (acpitz):

```
/sys/class/thermal/thermal_zone0/type          → acpitz
/sys/class/thermal/cooling_device6/type        → Fan   (max_state=1, cur_state=0)
/sys/class/thermal/cooling_device7/type        → Fan   (max_state=1, cur_state=0)
/sys/class/thermal/cooling_device8/type        → Fan   (max_state=1, cur_state=0)
/sys/class/thermal/cooling_device9/type        → Fan   (max_state=1, cur_state=0)
/sys/class/thermal/cooling_device10/type       → Fan   (max_state=1, cur_state=0)
```

Trip points on `thermal_zone0`: 40, 45, 50, 55, 100, 105°C. The board never reaches these, so every cooling device stays at `cur_state=0`.

### No hwmon fan/PWM endpoints (stock kernel)

The stock Unraid `it87` module doesn't detect the IT8613E chip:

```bash
find /sys/class/hwmon -name "pwm*" -o -name "fan*_input"
# (no output)

modprobe it87 force_id=0x8613
# modprobe: ERROR: could not insert 'it87': No such device
```

**Update:** The IT8613E _does_ exist on the DXP4800+ at ISA port `0x0a30` (non-standard, which is why auto-detection fails). Installing the [ich777/unraid-it87-driver](https://github.com/ich777/unraid-it87-driver) plugin (which uses the [frankcrawford/it87](https://github.com/frankcrawford/it87) fork) exposes full PWM fan control and RPM monitoring.

### Thermal throttling

CPU frequency under load with turbo enabled (factory paste):

```
cpu MHz: 2258.308    # P-core throttled from 4.1 GHz
cpu MHz: 900.007     # E-cores throttled from 3.0 GHz
```

## The Fix

Three steps, in order of impact. Most units will be fully fixed after Steps 1 and 2.

### Step 1: Repaste with Spread Technique (critical)

The factory thermal paste only covers ~40% of the bare die. Repasting alone dropped P-core temps by 21°C under sustained turbo load.

**Important: Use the spread technique, not dots.** The Pentium Gold 8505 is a bare die with no IHS. Dot/X methods rely on mounting pressure to spread paste across an IHS — on a bare die, they leave gaps. Pre-spread a thin, even layer across the entire die surface before mounting the heatsink.

The difference between paste application methods is dramatic:

| Method | P-core Temp | E-core Temp | Notes |
|--------|-------------|-------------|-------|
| Dot method (Arctic MX-6) | 100°C | 83°C | Still hits thermal limit, but holds 3.9 GHz |
| **Spread method (Arctic MX-6)** | **79°C** | **71°C** | 21°C cooler than dots. Full turbo, no throttle. |

The first repaste attempt used the dot method and left uneven coverage — the die center was well-covered but edges had thin spots. The second attempt with a proper full-die spread dropped temps by another 21°C. On a bare die CPU, paste technique matters as much as paste quality.

**How to repaste:**

1. Remove the 4 heatsink screws (Phillips)
2. Clean old paste from both the die and heatsink with isopropyl alcohol
3. Apply a small amount of paste (Arctic MX-6 or similar) to the die
4. Use a plastic spreader or card edge to spread a thin, even layer covering the entire die surface — no gaps at edges
5. Remount the heatsink evenly

### Step 2: BIOS SmartFan Tuning

The default BIOS fan curves are too conservative. In the BIOS SmartFan settings, set aggressive curves so the fans ramp up before the CPU gets hot:

**CPU Fan:**

| Setting | Value |
|---------|-------|
| Start PWM | 100 |
| Start Temp | 40°C |
| Slope PWM/°C | 15 |
| Full Speed Temp | 75°C |

**SYS Fan:**

| Setting | Value |
|---------|-------|
| Start PWM | 80 |
| Start Temp | 35°C |
| Slope PWM/°C | 10 |
| Full Speed Temp | 65°C |

These settings ensure the fans are already at full speed well before the CPU approaches thermal limits. With the repaste from Step 1, this keeps the CPU at 85°C under sustained all-core turbo load — hot but stable, no throttling.

### Step 3: Disable Turbo Boost (optional fallback)

If Steps 1 and 2 aren't sufficient for your unit, or if you want the coolest possible temps, disable turbo boost at the OS level:

```bash
echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
```

Make it permanent by adding to `/boot/config/go` (Unraid's startup script):

```bash
# Disable turbo boost - optional fallback if repaste + BIOS tuning isn't enough
echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
```

To re-enable temporarily (for benchmarks, encoding):

```bash
echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo
```

With turbo disabled, the CPU holds 40-43°C at idle and 45-49°C under sustained load at the 1.2 GHz base clock.

### Optional: CPU-Driven Fan Control Script (safety net)

A bash script that monitors `coretemp` and toggles all five ACPI fan cooling devices based on CPU temperature instead of board temperature.

- Fans ON when CPU >= 75°C
- Fans OFF when CPU <= 50°C
- 2-minute minimum on-time to prevent oscillation

With Steps 1+2 applied, this script is rarely needed. It's a safety net for edge cases.

The full script is at [`cpu-temp-fan-control.sh`](cpu-temp-fan-control.sh).

**Deploy via Unraid User Scripts plugin:**

```bash
# Create the User Script
mkdir -p /boot/config/plugins/user.scripts/scripts/cpu-temp-fan-control

# Copy the script
cp cpu-temp-fan-control.sh /boot/config/plugins/user.scripts/scripts/cpu-temp-fan-control/script

# Set schedule and name
echo '"At Startup of Array"' > /boot/config/plugins/user.scripts/scripts/cpu-temp-fan-control/schedule
echo 'cpu-temp-fan-control' > /boot/config/plugins/user.scripts/scripts/cpu-temp-fan-control/name

# Start it now without rebooting
nohup bash /boot/config/plugins/user.scripts/scripts/cpu-temp-fan-control/script </dev/null >/dev/null 2>&1 &
```

**Verify:**

```bash
sensors | grep "CPU Temp"
cat /var/log/cpu-fan-control.log
```

### Configuration

Edit the variables at the top of the script:

| Variable | Default | Purpose |
|----------|---------|---------|
| `THRESHOLD_ON` | 75 | Fans turn on above this temp (°C) |
| `THRESHOLD_OFF` | 50 | Fans turn off below this temp (°C) |
| `MIN_ON_SECS` | 120 | Minimum seconds fans stay on before turning off |
| `INTERVAL` | 5 | Seconds between temperature checks |

The 25°C hysteresis gap is intentional. Binary fans cool aggressively — without the gap and minimum hold time, the fans cycle on/off every few seconds.

## Test Results

All tests on 2026-03-11 (stock paste), 2026-03-17 (repaste with dots), and 2026-03-19 (repaste with spread + BIOS tuning). Sustained load from `find` processes pegging cores at 100% plus RoonServer indexing a music library at ~30% CPU.

### Complete Results Table

| Configuration | P-core Temp | P-core Freq | E-core Temp | E-core Freq | Throttle? |
|---------------|-------------|-------------|-------------|-------------|-----------|
| Factory paste, stock BIOS | 100°C | 2.2 GHz | 100°C | 900 MHz | Yes, severe |
| Factory paste, max fans (PWM 255) | 100°C | 2.2 GHz | 100°C | 900 MHz | Yes — cooler can't keep up |
| Repaste (dot method), stock BIOS | 100°C | 3.9 GHz | 83°C | 2.8 GHz | Thermal limit but near-full speed |
| **Repaste (spread), stock BIOS** | **79°C** | **3.8 GHz** | **71°C** | **2.8 GHz** | **No** |
| **Repaste (spread) + aggressive BIOS** | **85°C** | **3.65 GHz** | **77°C** | **2.8 GHz** | **No** |
| Factory paste, turbo OFF | 45-49°C | 1.2 GHz | ~45°C | 0.9 GHz | No (base clock only) |
| Repaste (spread), turbo OFF | 40-43°C | 1.2 GHz | ~40°C | 0.9 GHz | No (base clock only) |

Key takeaways:

- **Factory paste + any fan speed = throttle.** Even at max RPM, the cooler can't keep up because the paste barely contacts the die.
- **Dot vs. spread repaste = 21°C difference.** On a bare die CPU, paste technique matters enormously.
- **Repaste (spread) alone fixes throttling.** 79°C at 3.8 GHz with stock BIOS fan curves.
- **Adding aggressive BIOS curves trades a few degrees for sustained stability.** 85°C at 3.65 GHz is hotter than stock BIOS (79°C) because the aggressive fan curve is optimized for preventing thermal runaway under worst-case loads, not minimum steady-state temps. Both configurations run throttle-free.

### Idle Temperatures

| Configuration | Idle Temp |
|---------------|-----------|
| Factory paste | ~50°C |
| Repaste (spread) + aggressive BIOS | ~40°C |
| Turbo OFF (any paste) | 40-45°C |

## Why Not Just Fix the Fans?

Fan speed helps, but the factory paste was the real bottleneck. Before repasting, max fans made zero difference — the heat couldn't transfer from the die to the heatsink efficiently enough for fan speed to matter.

After repasting with proper spread technique, the BIOS SmartFan curves become effective because heat actually reaches the heatsink. The combination of good thermal transfer + aggressive fan curves keeps turbo running indefinitely.

### IT8613E PWM control exists (after driver install)

The DXP4800+ _does_ have an IT8613E Super IO chip at ISA `0x0a30`. The stock Unraid `it87` module can't detect it, but installing the [ich777/unraid-it87-driver](https://github.com/ich777/unraid-it87-driver) plugin exposes full PWM control:

```
it8613-isa-0a30
fan2:         988 RPM
fan3:        1002 RPM
pwm2: 51  (enable=2, auto)
pwm3: 51  (enable=2, auto)
```

Variable speed works — setting `pwm3=200` ramps fan3 from 1019 to 1470 RPM. The BIOS runs both fans at ~PWM 51 (~1000 RPM) in auto mode.

### ACPI fans don't control the physical fans

The five ACPI Fan cooling devices (`cooling_device6-10`, `max_state=1`) are binary on/off, but they don't actually drive the physical fans. The IT8613E chip controls the fans independently via its own auto curve. Toggling ACPI `cur_state` has no measurable effect on fan RPM.

### Optional: Install the IT8613E driver anyway

While the BIOS SmartFan settings handle fan control, the it87 driver is useful for:

- **Fan RPM monitoring** — `sensors` shows actual fan speeds
- **Noise optimization** — adjust PWM curves via FanCtrlPlus to run quieter at idle
- **Diagnostics** — verify fans are spinning and healthy

Install the [ich777/unraid-it87-driver](https://github.com/ich777/unraid-it87-driver) plugin from Community Apps, or manually:

```bash
# Download the pre-built driver for your kernel
wget -O /boot/config/plugins/it87-driver/it87.txz \
  "https://github.com/ich777/unraid-it87-driver/releases/download/$(uname -r)/it87-20260114-$(uname -r)-1.txz"

# Install and load
installpkg /boot/config/plugins/it87-driver/it87.txz
depmod -a
modprobe it87 ignore_resource_conflict=1

# Verify
sensors | grep -A5 it8613
```

## Compatibility

Tested on the DXP4800+ with Unraid 7.2.4. May apply to:

- **Other UGREEN NAS models** with Intel Alder Lake-N CPUs (N100, N305, etc.) that have similar thermal paste quality and ACPI fan management.
- **Any Intel system** using the `intel_pstate` driver — the turbo boost fix is generic.
- **Any Linux system** with ACPI Fan cooling devices — the fan script is portable.

### How to check if your system is affected

```bash
# 1. CPU hot while board cool?
sensors

# 2. No PWM fan control?
find /sys/class/hwmon -name "pwm*"
# If empty, no PWM.

# 3. Turbo enabled?
cat /sys/devices/system/cpu/intel_pstate/no_turbo
# 0 = turbo on

# 4. Binary ACPI fans?
for dev in /sys/class/thermal/cooling_device*; do
  echo "$dev: $(cat $dev/type) max=$(cat $dev/max_state)"
done
# Fan with max_state=1 = binary on/off
```

## FAQ

**Will disabling turbo hurt NAS performance?**

With repaste + BIOS tuning (Steps 1+2), you no longer need to disable turbo. The CPU runs at full turbo speeds under sustained load without throttling. If you still choose to disable turbo: for file serving, Docker, media streaming, the 1.2 GHz base clock handles them fine. You'll notice the difference in CPU-heavy tasks like HandBrake encoding.

**Do I need to spread the paste or can I use the dot method?**

Spread. The Pentium Gold 8505 is a bare die with no IHS (integrated heat spreader). Dot and X methods rely on IHS mounting pressure to spread paste evenly — on a bare die, they leave uneven coverage with gaps at the edges. In testing, the spread method ran 21°C cooler than the dot method with the same paste (Arctic MX-6). Pre-spread a thin, even layer across the entire die surface before mounting the heatsink.

**Is this a hardware defect?**

It's a combination of poor factory paste application and a firmware design choice. The paste coverage (~40% of the die) is well below acceptable for a bare die CPU. The ACPI fan binding (board temp instead of CPU temp) compounds the problem. UGOS has its own fan daemon that reads CPU temp directly, so the issue only manifests when running Unraid or other Linux distributions.

**Will a BIOS update fix this?**

A BIOS update could fix the ACPI thermal zone binding and fan curves, but it can't fix the factory paste. Repasting is a physical fix that no firmware update can replace.

**Can I get variable fan speed?**

Yes. Either tune the BIOS SmartFan settings (recommended — see Step 2), or install the [ich777/unraid-it87-driver](https://github.com/ich777/unraid-it87-driver) plugin for OS-level PWM control via `/sys/class/hwmon/`.

**Does this affect drive temperatures?**

No. The ACPI fan curve based on board temp works fine for drives — their temps correlate with board/ambient temp, not CPU temp.

## Emergency Commands

```bash
# Force all fans on immediately
for i in 6 7 8 9 10; do echo 1 > /sys/class/thermal/cooling_device${i}/cur_state; done

# Disable turbo boost immediately
echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
```

## License

MIT. Do what you want with it.
