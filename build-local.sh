#!/bin/bash
set -e

# Configurable variables (can be overridden with environment variables)
UBOOT_VERSION="${UBOOT_VERSION:-v2026.01}"
UBOOT_URL="${UBOOT_URL:-https://github.com/u-boot/u-boot/archive/refs/tags/${UBOOT_VERSION}.tar.gz}"
UBOOT_SHA256="${UBOOT_SHA256:-03bb43c58d2343ee48dd191e0f181f0108425b179d84519add3a977071c3f654}"
UBOOT_SHA512="${UBOOT_SHA512:-bf621285c526afbd22886ace2f04554dad3edc0b0d3c1bd095a851abe6e78676d1197904670a02e745959d83825bc798136970b9b1b87759c1891e4e77e11c01}"

NVIDIA_L4T_VERSION="${NVIDIA_L4T_VERSION:-r36.4.4}"
NVIDIA_L4T_URL="${NVIDIA_L4T_URL:-https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.4/release/Jetson_Linux_r36.4.4_aarch64.tbz2}"
NVIDIA_L4T_SHA256="${NVIDIA_L4T_SHA256:-a6ce11c22100ab0976e419959182417c83d62f4272501bc8714f2e076e010f3b}"
NVIDIA_L4T_SHA512="${NVIDIA_L4T_SHA512:-eccea1d2ce1907c853b1a282aa4c018585b001633c36452e33f166a4ef507da009fec6487d6a8f8b97054e787c6d79a9b72a8362712956e9e441cfba5c7df599}"

DOWNLOADS_DIR="${DOWNLOADS_DIR:-${HOME}/_downloads}"

# Parse command line arguments
CLEAN=false
if [ "$1" = "--clean" ]; then
    CLEAN=true
    shift
fi

# Clean previous build if requested
if [ "$CLEAN" = true ]; then
    echo "Cleaning previous build..."
    rm -rf _out
fi

# Create output directory and downloads directory
mkdir -p _out/{u-boot,installers,dtb}
mkdir -p "$DOWNLOADS_DIR"

# Function to verify checksum
verify_checksum() {
    local file=$1
    local expected=$2
    local algorithm=${3:-sha256}
    if [ -f "$file" ]; then
        local actual
        case $algorithm in
            sha256) actual=$(sha256sum "$file" | cut -d' ' -f1) ;;
            sha512) actual=$(sha512sum "$file" | cut -d' ' -f1) ;;
            *) echo "Unsupported algorithm: $algorithm"; return 1 ;;
        esac
        [ "$actual" = "$expected" ]
    else
        return 1
    fi
}

echo "Downloading and verifying sources..."

# Download NVIDIA L4T package if needed
NVIDIA_L4T_TARBALL="$DOWNLOADS_DIR/Jetson_Linux_${NVIDIA_L4T_VERSION}_aarch64.tbz2"
if ! verify_checksum "$NVIDIA_L4T_TARBALL" "$NVIDIA_L4T_SHA256"; then
    echo "Downloading NVIDIA L4T $NVIDIA_L4T_VERSION..."
    curl -L "$NVIDIA_L4T_URL" -o "$NVIDIA_L4T_TARBALL"
    
    # Verify downloaded file
    if ! verify_checksum "$NVIDIA_L4T_TARBALL" "$NVIDIA_L4T_SHA256"; then
        echo "ERROR: Downloaded NVIDIA L4T tarball checksum mismatch!"
        echo "Expected: $NVIDIA_L4T_SHA256"
        echo "Got:      $(sha256sum "$NVIDIA_L4T_TARBALL" | cut -d' ' -f1)"
        exit 1
    fi
else
    echo "NVIDIA L4T package already downloaded and verified."
fi

echo "Building U-Boot..."
cd _out/u-boot

# U-Boot source details
UBOOT_TARBALL="u-boot-${UBOOT_VERSION}.tar.gz"

# Download U-Boot source if needed
if ! verify_checksum "$UBOOT_TARBALL" "$UBOOT_SHA256"; then
    echo "Downloading U-Boot $UBOOT_VERSION..."
    curl -L "$UBOOT_URL" -o "$UBOOT_TARBALL"
    
    # Verify downloaded file
    if ! verify_checksum "$UBOOT_TARBALL" "$UBOOT_SHA256"; then
        echo "ERROR: Downloaded U-Boot tarball checksum mismatch!"
        echo "Expected: $UBOOT_SHA256"
        echo "Got:      $(sha256sum "$UBOOT_TARBALL" | cut -d' ' -f1)"
        exit 1
    fi
else
    echo "U-Boot tarball already downloaded and verified."
fi

# Extract and build only if binaries don't exist
if [ ! -f u-boot-jetson-nano.bin ] || [ ! -f dtb-jetson-nano.dtb ] || [ ! -f dtb-jetson-orin-nano.dtb ] || [ ! -f dtb-jetson-agx-orin.dtb ]; then
    echo "Extracting and building U-Boot..."
    tar xf "$UBOOT_TARBALL" --strip-components=1
    
    # Extract NVIDIA L4T DTBs
    echo "Extracting NVIDIA L4T DTBs..."
    mkdir -p nvidia-dtbs
    tar -xf "$NVIDIA_L4T_TARBALL" -C nvidia-dtbs --strip-components=1
    
    # Find and copy required DTB files from L4T package
    echo "Processing NVIDIA DTB files..."
    
    # Orin Nano: Use standard variant (0000 revision)
    find nvidia-dtbs -path "*/dtb/tegra234-p3768-0000+p3767-0000*.dtb" -not -name "*nv*" -exec cp {} dtb-jetson-orin-nano.dtb \; || \
    find nvidia-dtbs -path "*/dtb/tegra234-p3768-*+p3767-*.dtb" -not -name "*nv*" | head -1 | xargs -I {} cp {} dtb-jetson-orin-nano.dtb || \
    echo "Warning: Orin Nano DTB not found in L4T package"
    
    # AGX Orin: Use standard variant (0000 revision)  
    find nvidia-dtbs -path "*/dtb/tegra234-p3737-0000+p3701-0000*.dtb" -not -name "*nv*" -exec cp {} dtb-jetson-agx-orin.dtb \; || \
    find nvidia-dtbs -path "*/dtb/tegra234-p3737-*+p3701-*.dtb" -not -name "*nv*" | head -1 | xargs -I {} cp {} dtb-jetson-agx-orin.dtb || \
    echo "Warning: AGX Orin DTB not found in L4T package"
    
    # Copy NVIDIA DTBs to shared dtb directory
    [ -f dtb-jetson-orin-nano.dtb ] && cp dtb-jetson-orin-nano.dtb ../dtb/tegra234-p3768-0000+p3767-0000.dtb
    [ -f dtb-jetson-agx-orin.dtb ] && cp dtb-jetson-agx-orin.dtb ../dtb/tegra234-p3701-0000+p3737-0000.dtb
    
    # Build for each Jetson model
    export CROSS_COMPILE=aarch64-linux-gnu-
    export ARCH=arm64
    
    # Jetson Nano
    echo "Building U-Boot for Jetson Nano..."
    make p3450-0000_defconfig
    sed -i "s/CONFIG_TOOLS_LIBCRYPTO=y/# CONFIG_TOOLS_LIBCRYPTO is not set/" .config
    make -j $(nproc) HOSTLDLIBS_mkimage="-lssl -lcrypto"
    cp u-boot.bin u-boot-jetson-nano.bin
    
    # Copy Jetson Nano DTB if it exists
    if [ -f arch/arm/dts/tegra210-p3450-0000.dtb ]; then
        cp arch/arm/dts/tegra210-p3450-0000.dtb dtb-jetson-nano.dtb
        cp arch/arm/dts/tegra210-p3450-0000.dtb ../dtb/tegra210-p3450-0000.dtb
    fi
    
    echo "Using prebuilt NVIDIA DTBs for Orin models (mainline U-Boot doesn't have Tegra234 configs yet):"
    ls -la dtb-jetson-*.dtb 2>/dev/null || echo "No DTBs found"
else
    echo "U-Boot binaries and DTBs already built."
fi

cd ../..

echo "Building installers..."
for installer in jetson_nano jetson_orin_nano jetson_agx_orin; do
    if [ -d "installers/$installer/src" ]; then
        output_file="_out/installers/${installer}_installer"
        if [ ! -f "$output_file" ] || [ "installers/$installer/src/main.go" -nt "$output_file" ]; then
            echo "Building $installer installer..."
            cd installers/$installer/src
            go mod download
            CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o ../../../$output_file .
            cd ../../..
        else
            echo "$installer installer is up to date."
        fi
    fi
done

echo "Build complete! Artifacts are in _out/"
echo ""
echo "U-Boot binaries:"
ls -la _out/u-boot/*.bin 2>/dev/null || echo "  No U-Boot binaries found"
echo ""
echo "Device Tree Blobs:"
ls -la _out/dtb/*.dtb 2>/dev/null || echo "  No DTB files found"
echo ""
echo "Installer binaries:"
ls -la _out/installers/ 2>/dev/null || echo "  No installer binaries found"
echo ""
echo "Usage:"
echo "  ./build-local.sh          # Incremental build"
echo "  ./build-local.sh --clean  # Clean and full rebuild"