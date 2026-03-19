# UGREEN DXP4800+ Thermal Fix

The DXP4800+ throttles under sustained load because factory thermal paste covers only ~40% of the bare die, and BIOS fan curves are too conservative.

**Fix:** Repaste (spread technique) + BIOS SmartFan tuning. Full turbo, no throttling.

## The Fix

### 1. Repaste with spread technique

The 8505 is bare die — no IHS. Dot/pea methods leave gaps. **Spread a thin even layer across the entire die surface.** Spread was 21°C cooler than dots with the same paste (Arctic MX-6).

[Teardown video](https://youtu.be/nX61c-l4I_s)

### 2. BIOS SmartFan tuning

Enter BIOS: **Ctrl+F12** at boot → **Advanced → Hardware Monitor**.

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

### 3. Disable turbo (optional fallback)

Only if Steps 1+2 aren't enough:

```bash
echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
```

Add to `/boot/config/go` to persist.

## Results

| Configuration | P-core | E-cores | Throttle? |
|---------------|--------|---------|-----------|
| Factory paste, stock BIOS | 100°C / 2.2 GHz | 100°C / 900 MHz | Yes |
| Factory paste, max fans | 100°C / 2.2 GHz | 100°C / 900 MHz | Yes — paste is the bottleneck |
| Repaste (dots) | 100°C / 3.9 GHz | 83°C / 2.8 GHz | P-core at limit |
| Repaste (spread) | 79°C / 3.8 GHz | 71°C / 2.8 GHz | **No** |
| **Repaste (spread) + BIOS tuning** | **85°C / 3.65 GHz** | **77°C / 2.8 GHz** | **No** |

## Notes

- UGOS isn't affected — it has its own fan daemon (`hwmonitor`) that bypasses the broken ACPI binding.
- The IT8613E Super IO chip exists at ISA `0x0a30`. The [ich777/unraid-it87-driver](https://github.com/ich777/unraid-it87-driver) plugin exposes fan RPM monitoring if you want it.
- ACPI fan cooling devices are bound to board temp (~28°C always) and don't control the physical fans. The BIOS SmartFan reads CPU temp directly.
- Tested on DXP4800+ with Unraid 7.2.4.

## License

MIT
