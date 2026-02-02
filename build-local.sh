#!/bin/bash
set -e

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

# Create output directory
mkdir -p _out/{u-boot,installers}

echo "Building U-Boot..."
cd _out/u-boot

# U-Boot source details
UBOOT_VERSION="v2026.01"
UBOOT_URL="https://github.com/u-boot/u-boot/archive/refs/tags/${UBOOT_VERSION}.tar.gz"
UBOOT_TARBALL="u-boot-${UBOOT_VERSION}.tar.gz"
EXPECTED_SHA256="03bb43c58d2343ee48dd191e0f181f0108425b179d84519add3a977071c3f654"

# Function to verify checksum
verify_checksum() {
    local file=$1
    local expected=$2
    if [ -f "$file" ]; then
        local actual=$(sha256sum "$file" | cut -d' ' -f1)
        [ "$actual" = "$expected" ]
    else
        return 1
    fi
}

# Download U-Boot source if needed
if ! verify_checksum "$UBOOT_TARBALL" "$EXPECTED_SHA256"; then
    echo "Downloading U-Boot $UBOOT_VERSION..."
    curl -L "$UBOOT_URL" -o "$UBOOT_TARBALL"
    
    # Verify downloaded file
    if ! verify_checksum "$UBOOT_TARBALL" "$EXPECTED_SHA256"; then
        echo "ERROR: Downloaded tarball checksum mismatch!"
        echo "Expected: $EXPECTED_SHA256"
        echo "Got:      $(sha256sum "$UBOOT_TARBALL" | cut -d' ' -f1)"
        exit 1
    fi
else
    echo "U-Boot tarball already downloaded and verified."
fi

# Extract and build only if binaries don't exist
if [ ! -f u-boot-jetson-nano.bin ]; then
    echo "Extracting and building U-Boot..."
    tar xf "$UBOOT_TARBALL" --strip-components=1
    
    # Build for each Jetson model
    export CROSS_COMPILE=aarch64-linux-gnu-
    export ARCH=arm64
    
    # Jetson Nano
    make p3450-0000_defconfig
    sed -i "s/CONFIG_TOOLS_LIBCRYPTO=y/# CONFIG_TOOLS_LIBCRYPTO is not set/" .config
    make -j $(nproc) HOSTLDLIBS_mkimage="-lssl -lcrypto"
    cp u-boot.bin u-boot-jetson-nano.bin
    
    # Orin models (if configs exist)
    for config in p3767-0000_defconfig p3701-0000_defconfig; do
        if [ -f configs/$config ]; then
            model=$(echo $config | cut -d'_' -f1)
            make distclean
            make $config
            sed -i "s/CONFIG_TOOLS_LIBCRYPTO=y/# CONFIG_TOOLS_LIBCRYPTO is not set/" .config
            make -j $(nproc) HOSTLDLIBS_mkimage="-lssl -lcrypto"
            cp u-boot.bin u-boot-${model}.bin
        fi
    done
else
    echo "U-Boot binaries already built."
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
echo "Installer binaries:"
ls -la _out/installers/ 2>/dev/null || echo "  No installer binaries found"
echo ""
echo "Usage:"
echo "  ./build-local.sh          # Incremental build"
echo "  ./build-local.sh --clean  # Clean and full rebuild"