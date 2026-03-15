# UGREEN DXP4800+ Thermal Fix for Unraid

The DXP4800+ thermal throttles under sustained load because its ACPI firmware controls fans based on board temperature, not CPU temperature. The board sits at ~28°C no matter what, so the fans never ramp up. The CPU's only option is to throttle itself.

This documents the problem, the diagnosis, and two fixes that bring the CPU from 100°C down to 45-49°C.

## The Problem

The UGREEN DXP4800+ (Intel Pentium Gold 8505) hits 100°C and thermal throttles during moderate sustained work — Roon library indexing, folder caching scans, anything that holds a core at 100% for more than a few seconds.

The root cause is in the ACPI thermal tables. All five fan cooling devices are bound to the board temperature sensor (`acpitz` / `thermal_zone0`), not the CPU sensor (`coretemp`). The board reads ~28°C regardless of CPU load, so the firmware never tells the fans to spin up. The CPU's only thermal protection is throttling its own clock speed.

Fan speed turns out to be irrelevant — [even at max RPM, the cooler can't keep up with turbo heat](#why-not-just-fix-the-fans).

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

**Update:** The IT8613E _does_ exist on the DXP4800+ at ISA port `0x0a30` (non-standard, which is why auto-detection fails). Installing the [ich777/unraid-it87-driver](https://github.com/ich777/unraid-it87-driver) plugin (which uses the [frankcrawford/it87](https://github.com/frankcrawford/it87) fork) exposes full PWM fan control and RPM monitoring. See [Fan Speed Doesn't Matter](#why-not-just-fix-the-fans) for why this doesn't change the fix.

### Thermal throttling

CPU frequency under load with turbo enabled:

```
cpu MHz: 2258.308    # P-core throttled from 4.1 GHz
cpu MHz: 900.007     # E-cores throttled from 3.0 GHz
```

## The Fix

Two changes at the OS level. No hardware mods, no BIOS changes.

### Part 1: Disable Turbo Boost (primary fix)

The Pentium Gold 8505 P-core turbos to 4.1 GHz. The DXP4800+ enclosure cannot dissipate the heat this generates under sustained load. At base clock (1.2 GHz), the CPU holds 45-49°C even with cores pegged at 100%.

```bash
echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
```

Make it permanent by adding to `/boot/config/go` (Unraid's startup script):

```bash
# Disable turbo boost - DXP4800+ cannot cool the P-core at 4.1GHz
echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
```

To re-enable temporarily (for benchmarks, encoding):

```bash
echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo
```

### Part 2: CPU-Driven Fan Control Script (safety net)

A bash script that monitors `coretemp` and toggles all five ACPI fan cooling devices based on CPU temperature instead of board temperature.

- Fans ON when CPU >= 75°C
- Fans OFF when CPU <= 50°C
- 2-minute minimum on-time to prevent oscillation

With turbo disabled, this script rarely fires — the CPU stays well below 75°C. It's a safety net for edge cases.

The full script is at [`scripts/cpu-temp-fan-control.sh`](../scripts/cpu-temp-fan-control.sh).

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

All tests on 2026-03-11. Sustained load from `find` processes pegging cores at 100% plus RoonServer indexing a music library at ~30% CPU.

| Configuration | CPU Temp | Behavior |
|---------------|----------|----------|
| Turbo ON, firmware default (fans ~1000 RPM) | 99-100°C sustained | Thermal throttling. P-core drops from 4.1 to ~2.2 GHz. |
| Turbo ON, IT8613E PWM max (fan2: 3426, fan3: 1781 RPM) | 100°C in 5 seconds | Max fans make no difference. Cooler bottleneck. |
| Turbo ON, ACPI fans forced ON | 50-100°C oscillating (5-10s cycle) | Fans cool CPU, turbo ramps up, temp spikes again. |
| Turbo ON, fans ON + external AC Infinity S7-P 140mm | 50-100°C oscillating | External fans made zero measurable difference. |
| **Turbo OFF, any fan config** | **45-49°C steady** | No throttling. Base clock 1.2 GHz. |

The 50-100°C oscillation with turbo on is a thermal throttle cycle: boost to 4.1 GHz, hit 100°C, throttle, cool to ~50°C, boost again. Every 5-10 seconds, indefinitely.

External fans (AC Infinity Multifan S7-P blowing directly on the enclosure) changed nothing. The bottleneck is the CPU package and heatsink, not ambient airflow. Board temp stayed at 28°C and NVMe at 46°C regardless of configuration.

## Why Not Just Fix the Fans?

We tested this. **The cooler physically cannot dissipate turbo boost heat, regardless of fan speed.**

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

### Max fans + turbo = still 100°C

We ran both fans at maximum (fan2: 3426 RPM, fan3: 1781 RPM), re-enabled turbo, and stress-tested. **CPU hit 100°C in 5 seconds.** Identical to having the fans at idle.

| Test | fan2 RPM | fan3 RPM | CPU Temp | Result |
|------|----------|----------|----------|--------|
| Default auto (PWM 51) + turbo | 988 | 1002 | 100°C in 5s | Throttle |
| Max fans (PWM 255) + turbo | 3426 | 1781 | 100°C in 5s | Throttle |
| Any fan speed + **turbo off** | any | any | **45-49°C** | Stable |

The bottleneck is the CPU heatsink/package, not airflow. The DXP4800+ enclosure was designed for the 8505 at base clock, not at sustained turbo.

### ACPI fans don't control the physical fans

The five ACPI Fan cooling devices (`cooling_device6-10`, `max_state=1`) are binary on/off, but they don't actually drive the physical fans. The IT8613E chip controls the fans independently via its own auto curve. Toggling ACPI `cur_state` has no measurable effect on fan RPM.

### Optional: Install the IT8613E driver anyway

While it won't fix the thermal throttling, the it87 driver is useful for:

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

- **Other UGREEN NAS models** with Intel Alder Lake-N CPUs (N100, N305, etc.) that lack IT8613E and use ACPI fan management.
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

For file serving, Docker, media streaming — no. These are throughput workloads. The 1.2 GHz base clock handles them fine. You'll notice it in CPU-heavy tasks like HandBrake encoding. Re-enable turbo temporarily for those.

**Is this a hardware defect?**

It's a firmware design choice. UGOS has its own fan daemon that reads CPU temp directly. When you run Unraid or any other Linux, you bypass UGOS, and the ACPI firmware's board-temp fan curve is inadequate.

**Will a BIOS update fix this?**

A BIOS update could fix the ACPI thermal zone binding (board temp → CPU temp), but the underlying issue is the cooler design. Even at max fan speed, the heatsink can't dissipate turbo heat. A BIOS fix would let the fans ramp harder under load, but turbo would still thermal throttle under sustained workloads.

**Can I get variable fan speed?**

Yes. Install the [ich777/unraid-it87-driver](https://github.com/ich777/unraid-it87-driver) plugin — it loads the frankcrawford `it87` fork which detects the IT8613E chip at ISA `0x0a30`. This exposes full PWM control and RPM monitoring via `/sys/class/hwmon/`. Useful for noise optimization, but doesn't change the need to disable turbo.

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
