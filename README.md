# UGREEN DXP4800+ Thermal Fix for Unraid

The DXP4800+ thermal throttles under sustained load because its ACPI firmware controls fans based on board temperature, not CPU temperature. The board sits at ~28°C no matter what, so the fans never ramp up. The CPU's only option is to throttle itself.

This documents the problem, the diagnosis, and two fixes that bring the CPU from 100°C down to 45-49°C.

## The Problem

The UGREEN DXP4800+ (Intel Pentium Gold 8505) hits 100°C and thermal throttles during moderate sustained work — Roon library indexing, folder caching scans, anything that holds a core at 100% for more than a few seconds.

The root cause is in the ACPI thermal tables. All five fan cooling devices are bound to the board temperature sensor (`acpitz` / `thermal_zone0`), not the CPU sensor (`coretemp`). The board reads ~28°C regardless of CPU load, so the firmware never tells the fans to spin up. The CPU's only thermal protection is throttling its own clock speed.

Existing tools can't help:

- **Unraid Autofan plugin** — needs hwmon PWM endpoints. The DXP4800+ has none.
- **Community fan control** ([0n1cOn3/UGREEN-Fan-Control](https://github.com/0n1cOn3/UGREEN-Fan-Control), [ianplusplus/ugreenfancontrol](https://github.com/ianplusplus/ugreenfancontrol)) — both depend on the IT8613E Super IO chip, which exists on the DXP2800 but not the DXP4800+.
- **ACPI fan control via sysfs** — the cooling devices are binary on/off (`max_state=1`). No variable speed.

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

### No hwmon fan/PWM endpoints

```bash
find /sys/class/hwmon -name "pwm*" -o -name "fan*_input"
# (no output)

modprobe it87 force_id=0x8613
# modprobe: ERROR: could not insert 'it87': No such device
```

No hardware path to control fan speed. The Autofan plugin has nothing to work with.

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
| Turbo ON, firmware default (fans low) | 99-100°C sustained | Thermal throttling. P-core drops from 4.1 to ~2.2 GHz. |
| Turbo ON, ACPI fans forced ON | 50-100°C oscillating (5-10s cycle) | Fans cool CPU, turbo ramps up, temp spikes again. |
| Turbo ON, fans ON + external AC Infinity S7-P 140mm | 50-100°C oscillating | External fans made zero measurable difference. |
| **Turbo OFF, any fan config** | **45-49°C steady** | No throttling. Base clock 1.2 GHz. |

The 50-100°C oscillation with turbo on is a thermal throttle cycle: boost to 4.1 GHz, hit 100°C, throttle, cool to ~50°C, boost again. Every 5-10 seconds, indefinitely.

External fans (AC Infinity Multifan S7-P blowing directly on the enclosure) changed nothing. The bottleneck is the CPU package and heatsink, not ambient airflow. Board temp stayed at 28°C and NVMe at 46°C regardless of configuration.

## Why Not Just Fix the Fans?

The DXP4800+ doesn't expose the fan control interface that Linux tools expect.

**ACPI fans are binary.** `max_state=1` — on or off. Even forced to full blast, they can't keep up with turbo boost heat output. The test data shows this: fans on + turbo on = oscillating 50-100°C.

**No hwmon PWM endpoints.** No IT8613E chip on the DXP4800+ (the DXP2800 has one, which is why some community tools work on that model). Without hwmon PWM, the Autofan plugin, `fancontrol`, and both community UGREEN projects are non-starters.

**The EC probably has real fan control.** The DSDT references EC fields (`CFAN`) and methods (`ECWT`) that suggest variable speed capability — this is presumably what UGOS uses internally. Accessing it from Linux would require building `ec_sys` or `acpi_call` kernel modules for the Unraid kernel and reverse-engineering the register map. Possible, but a significant project with risk of hardware damage if you write the wrong register.

Disabling turbo is simpler, safer, and more effective.

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

Possibly, if UGREEN adds CPU temp to the ACPI thermal zone bindings. As of March 2026, no such update exists.

**Can I get variable fan speed?**

Not without reverse-engineering the EC registers. The DSDT has the hooks (`ECWT`, `CFAN`) but no one has mapped them yet. If you have EC documentation for these boards, please open an issue.

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
