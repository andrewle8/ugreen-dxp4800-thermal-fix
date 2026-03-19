# UGREEN DXP4800+ Thermal Fix

The DXP4800+ thermal throttles under sustained load. Two causes: factory thermal paste covers only ~40% of the bare die, and BIOS fan curves are too conservative.

**Fix:** Repaste with spread technique + tune BIOS SmartFan. Result: P-core 85°C at 3.65 GHz sustained, E-cores 77°C at 2.8 GHz. No throttling. Full turbo.

## The Problem

The Pentium Gold 8505 hits 100°C and throttles to 2.2 GHz (P-core) / 900 MHz (E-cores) during any sustained CPU load — Roon indexing, folder scans, transcoding, anything holding cores at 100% for more than a few seconds.

**Root causes:**

1. **Factory thermal paste is poorly applied.** Only ~40% of the bare die was covered. The 8505 has no IHS — it's exposed silicon making direct contact with the heatsink, so paste coverage is critical.

2. **BIOS fan curves are too conservative.** The default SmartFan settings keep fans at ~1000 RPM until the CPU is already hot. By the time they ramp, it's too late.

There's also an ACPI firmware issue (fans bound to board temp sensor instead of CPU temp), but it turns out the BIOS SmartFan controller reads CPU temp directly and works independently of ACPI. The ACPI bug is a red herring if you tune the BIOS.

## The Fix

### Step 1: Repaste with Spread Technique

The factory paste barely contacts the die. Repasting alone dropped P-core temps from 100°C to 79°C under sustained turbo.

**Use the spread technique, not dots.** The 8505 is a bare die — dot/pea methods rely on IHS mounting pressure to spread paste. On bare die, they leave gaps. In testing, spread ran 21°C cooler than dots with the same paste:

| Method | P-core | E-cores |
|--------|--------|---------|
| Factory paste | 100°C (throttled to 2.2 GHz) | 100°C (throttled to 900 MHz) |
| Repaste — dot method | 100°C (holds 3.9 GHz) | 83°C |
| **Repaste — spread method** | **79°C (3.8 GHz)** | **71°C** |

**How to repaste:**

1. Disassemble to reach the CPU heatsink ([teardown video](https://youtu.be/nX61c-l4I_s))
2. Remove heatsink screws in cross pattern, twist gently to break paste seal
3. Clean old paste off die and heatsink base with isopropyl alcohol
4. Apply paste to both silicon rectangles on the die
5. **Spread thin and even across the entire die surface** — edge to edge, no bare silicon
6. Mount heatsink straight down (don't slide), tighten screws in cross pattern

### Step 2: BIOS SmartFan Tuning

Enter BIOS with **Ctrl+F12** at boot. Navigate to **Advanced → Hardware Monitor**.

**CPU SmartFan:**

| Setting | Default | Set to |
|---------|---------|--------|
| Fan PWM Slope | 20 | **15** |
| Fan Start PWM | 51 | **100** |
| Fan Start Temperature | 45 | **40** |
| Fan Full Speed Temperature | 85 | **75** |

**SYS SmartFan1:**

| Setting | Default | Set to |
|---------|---------|--------|
| Fan PWM Slope | 35 | **10** |
| Fan Start PWM | 51 | **80** |
| Fan Start Temperature | 25 | **35** |
| Fan Full Speed Temperature | 80 | **65** |

This ramps fans to full speed at 75°C — well before the CPU reaches thermal limits. Combined with the repaste, sustained turbo runs at 85°C with no throttling.

### Step 3: Disable Turbo Boost (optional fallback)

Only needed if Steps 1+2 aren't enough for your unit.

```bash
# Disable turbo
echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo

# Make permanent (add to /boot/config/go)
echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo

# Re-enable
echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo
```

With turbo off, the CPU holds 40-43°C at idle and ~45°C under load at 1.2 GHz base clock.

## Test Results

All tests under sustained all-core load.

| Configuration | P-core Temp | P-core Freq | E-core Temp | E-core Freq | Throttle? |
|---------------|-------------|-------------|-------------|-------------|-----------|
| Factory paste, stock BIOS | 100°C | 2.2 GHz | 100°C | 900 MHz | Yes, severe |
| Factory paste, max fans | 100°C | 2.2 GHz | 100°C | 900 MHz | Yes — paste is the bottleneck |
| Repaste (dots), stock BIOS | 100°C | 3.9 GHz | 83°C | 2.8 GHz | P-core at limit, holds freq |
| Repaste (spread), stock BIOS | 79°C | 3.8 GHz | 71°C | 2.8 GHz | **No** |
| **Repaste (spread) + BIOS tuning** | **85°C** | **3.65 GHz** | **77°C** | **2.8 GHz** | **No** |
| Turbo OFF (any config) | 40-45°C | 1.2 GHz | ~40°C | 0.9 GHz | No (base clock) |

**Key findings:**
- Factory paste + any fan speed = throttle. The paste was the bottleneck, not the fans.
- Dot vs spread repaste = **21°C difference** on the same paste (Arctic MX-6).
- Repaste alone fixes throttling. BIOS tuning adds sustained stability.
- Max fans before repaste made zero difference. After repaste, fan curves matter.

## Diagnosis Details

### CPU vs board temperature (stock)

```
coretemp-isa-0000
CPU Temp:     +100.0°C  (high = +100.0°C, crit = +100.0°C)  ALARM (CRIT)

acpitz-acpi-0
temp1:         +27.8°C
```

CPU at 100°C. Board at 28°C. ACPI fans idle because they're bound to board temp.

### ACPI fan binding (informational)

Five ACPI Fan cooling devices bound to `thermal_zone0` (board temp). Trip points at 40-105°C on board temp — never reached, so ACPI fans stay off. This doesn't matter if you tune the BIOS SmartFan, which reads CPU temp directly and controls the physical fans independently of ACPI.

### IT8613E Super IO chip

The DXP4800+ has an IT8613E at ISA port `0x0a30` (non-standard, auto-detection fails). The [ich777/unraid-it87-driver](https://github.com/ich777/unraid-it87-driver) plugin exposes PWM fan control and RPM monitoring. Useful for diagnostics but not required — BIOS SmartFan handles fan control.

### UGOS vs third-party OS

UGOS has its own fan daemon (`hwmonitor`, config at `/etc/default/dxp4800plus.conf`) that reads CPU temp directly and bypasses the broken ACPI binding. Third-party OSes (Unraid, Proxmox, TrueNAS) don't have this daemon, which is why the ACPI issue only manifests outside UGOS.

## FAQ

**Do I need to spread the paste or can I use the dot method?**

Spread. The 8505 is bare die with no IHS. Dot methods leave gaps. In testing, spread was 21°C cooler than dots with the same paste.

**Will disabling turbo hurt NAS performance?**

With repaste + BIOS tuning, you don't need to disable turbo. If you do: file serving, Docker, media streaming are fine at 1.2 GHz base clock. CPU-heavy tasks (transcoding, encoding) will be noticeably slower.

**Is this a hardware defect?**

Poor factory paste application combined with conservative BIOS defaults. UGOS works around it with a custom fan daemon. UGREEN should improve QC on thermal paste application — 40% die coverage on a bare die CPU is unacceptable.

**Can I monitor fan speed?**

Install the [ich777/unraid-it87-driver](https://github.com/ich777/unraid-it87-driver) plugin. It detects the IT8613E at ISA `0x0a30` and exposes fan RPM and PWM control via `sensors`.

**Does this affect drive temperatures?**

No. Drives correlate with board/ambient temp, not CPU temp.

### How to check if you're affected

```bash
# CPU hot while board cool?
sensors

# Turbo enabled?
cat /sys/devices/system/cpu/intel_pstate/no_turbo
# 0 = turbo on
```

If CPU is near 100°C under load while board reads ~28°C, you have this issue.

## Compatibility

Tested on DXP4800+ with Unraid 7.2.4. The repaste applies to any DXP4800+ regardless of OS. BIOS SmartFan settings are OS-independent. The turbo disable fallback works on any Linux with `intel_pstate`.

## License

MIT
