# UGREEN DXP4800+ Thermal Fix

The DXP4800+ throttles under sustained load because factory thermal paste covers only ~40% of the bare die, and BIOS fan curves are too conservative.

**Fix:** Repaste (spread technique) + aggressive BIOS SmartFan tuning. Full turbo, no throttling, 77-79°C sustained.

## The Fix

### 1. Repaste with spread technique

The 8505 is a bare die (no IHS). Dot/pea methods leave gaps. **Spread a thin even layer across the entire die surface.** Spread was 21°C cooler than pea method with the same paste (Arctic MX-6).

### 2. BIOS SmartFan tuning

Enter BIOS: **Ctrl+F12** at boot → **Advanced → Hardware Monitor**.

The key insight: BIOS SmartFan reads CPU temp directly, not the broken ACPI board temp sensor (~28°C always). Setting aggressive curves here is the correct fan control mechanism.

**CPU SmartFan:**

| Setting | Default | Recommended (Noctua NF-A14) |
|---------|---------|---------------------------|
| Fan PWM Slope | 20 | **4** |
| Fan Start PWM | 51 | **80** |
| Fan Off Temperature Limit | 0 | **0** |
| Fan Start Temperature | 45 | **40** |
| Fan Full Speed Temperature | 85 | **80** |
| Extra Temperature Setting | 70 | **60** |
| Extra Slope Setting | 80 | **12** |

**SYS SmartFan1:**

| Setting | Default | Recommended (Noctua NF-A14) |
|---------|---------|---------------------------|
| Fan PWM Slope | 35 | **4** |
| Fan Start PWM | 51 | **60** |
| Fan Off Temperature Limit | 0 | **0** |
| Fan Start Temperature | 25 | **30** |
| Fan Full Speed Temperature | 80 | **65** |
| Extra Temperature Setting | 70 | **50** |
| Extra Slope Setting | 80 | **8** |

The Extra Temperature and Extra Slope settings create a two-stage fan curve: gentle ramp below the Extra Temp (primary slope), steep ramp above it (extra slope). This eliminates fan hunting/oscillation. With the stock fan or without a Noctua, use higher Start PWM values (100+) and a slope of 10-15.

## Results

| Configuration | P-core | E-cores | Throttle? |
|---------------|--------|---------|-----------|
| Factory paste, stock BIOS | 100°C / 2.2 GHz | 100°C / 900 MHz | Yes |
| Factory paste, max fans | 100°C / 2.2 GHz | 100°C / 900 MHz | Yes -- paste is the bottleneck |
| Repaste (pea) | 100°C / 3.9 GHz | 83°C / 2.8 GHz | P-core at limit |
| Repaste (spread) + conservative curves | 85°C / 3.65 GHz | 77°C / 2.8 GHz | No |
| **Repaste (spread) + aggressive curves** | **77-79°C / 3.8 GHz** | **63-70°C / 2.8 GHz** | **No** |

Idle temps: ~45-50°C with aggressive curves, ~50-55°C with conservative.

## Why It Throttles

1. **Factory paste** only contacts ~40% of the die. The paste isn't dried out -- it's just poorly applied (too little, uneven).
2. **ACPI firmware defect** -- fan cooling devices are bound to board temp (~28°C), not CPU temp. Kernel fan control never kicks in.
3. **Conservative stock BIOS curves** -- even the BIOS SmartFan defaults don't ramp fans fast enough for burst loads.

The heatsink base is flat. Poor thermal contact is entirely a paste application issue.

## Notes

- UGOS isn't affected. It has its own fan daemon (`hwmonitor`) that bypasses the broken ACPI binding.
- The IT8613E Super IO chip exists at ISA `0x0a30`. The [ich777/unraid-it87-driver](https://github.com/ich777/unraid-it87-driver) plugin exposes fan RPM monitoring if you want it.
- ACPI fan cooling devices (`cooling_device6-10`) are virtual and toggling them has no effect on physical fans. Don't waste time with ACPI fan scripts.
- The Unraid Dynamix Cache Dirs plugin runs `find` scans every ~10 min that spike one P-core to 100% for 30-60s. This is the primary heat source on an otherwise idle NAS.
- Tested on DXP4800+ (Intel Pentium Gold 8505) with Unraid 7.2.4.
