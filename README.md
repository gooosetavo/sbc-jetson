# sbc-jetson

This repository provides **overlay support for NVIDIA Jetson single-board computers in Talos Linux**. It creates custom installers that integrate NVIDIA Jetson hardware with Talos Linux, including proper U-Boot bootloader support, device tree configurations, and hardware-specific kernel parameters.

Support for this project is based on [NVIDIA embedded lifecycle](https://developer.nvidia.com/embedded/lifecycle).

## Project Overview

**sbc-jetson** enables Talos Linux to run on NVIDIA Jetson devices by:

- **Custom Installers**: Device-specific installers that handle hardware configuration during Talos installation
- **U-Boot Integration**: Tegra-optimized U-Boot bootloader support using the OE4T (OpenEmbedded for Tegra) fork
- **Device Tree Support**: Proper DTB (Device Tree Blob) installation for each Jetson variant
- **Hardware Configuration**: Optimized kernel boot parameters and system settings for Jetson hardware

## Supported Overlays

| Overlay Name | Board       | Tegra SoC | U-Boot Config   | Description         |
| ------------ | ----------- | --------- | --------------- | ------------------- |
| jetson_nano  | Jetson Nano | Tegra210  | p3450-0000      | Jetson Nano overlay |

### Current Architecture Details

- **U-Boot Version**: v2022.07 (OE4T fork)
- **Device Tree**: `nvidia/tegra210-p3450-0000.dtb`
- **Boot Configuration**: Serial console, security hardening, Talos dashboard disabled
- **Platform**: ARM64/AArch64

## Development

### Project Structure

```
├── artifacts/u-boot/          # U-Boot build configuration
├── installers/                # Device-specific installers
│   └── jetson_nano/           # Jetson Nano installer implementation
├── profiles/                  # Talos image profiles
└── internal/                  # Shared components
```

### Adding Support for Newer Jetson Models

To add support for newer Jetson devices (e.g., Orin Nano, AGX Orin):

1. **Create new installer directory**:
   ```
   installers/jetson_orin_nano/
   ```

2. **Implement installer** (based on `installers/jetson_nano/src/main.go`):
   ```go
   // Update device tree reference for new hardware
   dtb = "nvidia/tegra234-p3768-0000+p3767-0000.dtb"
   ```

3. **Add U-Boot configuration** in `artifacts/u-boot/pkg.yaml`:
   - Update to newer U-Boot version if required
   - Add appropriate defconfig (e.g., `p3767-0000_defconfig`)

### Updating U-Boot Version

Current U-Boot version can be updated in [`artifacts/u-boot/pkg.yaml`](artifacts/u-boot/pkg.yaml):

```yaml
# Current: v2022.07
- url: https://github.com/OE4T/u-boot-tegra/archive/refs/tags/v2022.07.tar.gz

# Update to newer version:
- url: https://github.com/OE4T/u-boot-tegra/archive/refs/tags/v2023.01.tar.gz
```

**Version Compatibility Reference**:

| Jetson Model | Tegra SoC | U-Boot Config | Minimum U-Boot Version |
|-------------|-----------|---------------|------------------------|
| Nano        | Tegra210  | p3450-0000    | v2021.10+             |
| Orin Nano   | Tegra234  | p3767-0000    | v2023.01+             |
| AGX Orin    | Tegra234  | p3701-0000    | v2023.01+             |

### Building

Build all components:
```bash
make
```

Build specific installer:
```bash
make jetson-nano-installer
```
