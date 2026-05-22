#!/bin/bash
set -e

# Buildroot variables
BINARIES_DIR="$1"
BOARD_DIR="board/swacs1d"
EFI_DIR="${BINARIES_DIR}/efi-part/EFI/BOOT"

# Compute the absolute path to Buildroot's build directory
BUILD_DIR="$(cd "${BINARIES_DIR}/../build" && pwd)"

echo "POST-IMAGE: Preparing Custom Shim + Grub Secure Boot structure..."

# Create clean execution targets
mkdir -p "${EFI_DIR}"
mkdir -p "${BINARIES_DIR}/efi-part"

# 1. Locate Shim inside Buildroot's package build directory
echo "POST-IMAGE: Searching for compiled shim binary..."
SHIM_SRC=$(find "${BUILD_DIR}" -type f -name "shimx64.efi" | head -n 1)

if [ -n "${SHIM_SRC}" ] && [ -f "${SHIM_SRC}" ]; then
    echo "POST-IMAGE: Located Shim at: ${SHIM_SRC}"
else
    echo "ERROR: shimx64.efi was not found in ${BUILD_DIR}. Ensure BR2_PACKAGE_SHIM=y is built."
    exit 1
fi

# 2. Verify Grub exists (Buildroot default outputs it into efi-part/EFI/BOOT/bootx64.efi)
ORIG_GRUB="${BINARIES_DIR}/efi-part/EFI/BOOT/bootx64.efi"
if [ ! -f "${ORIG_GRUB}" ]; then
    echo "ERROR: Original Grub binary not found at ${ORIG_GRUB}!"
    exit 1
fi

# 3. Re-arrange files to fit the strict Shim loading order
# Copy Shim to the primary boot file position
cp "${SHIM_SRC}" "${EFI_DIR}/BOOTX64.EFI"

# Move the original Grub binary right next to it, named exactly what Shim expects
mv "${ORIG_GRUB}" "${EFI_DIR}/grubx64.efi"

# Make sure the config profile is copied over
cp "${BOARD_DIR}/grub.cfg" "${EFI_DIR}/grub.cfg"

# 4. Handle Secure Boot Cryptographic Signing Operations
SB_KEY="${BOARD_DIR}/keys/db.key"
SB_CRT="${BOARD_DIR}/keys/db.crt"

if [ -f "$SB_KEY" ] && [ -f "$SB_CRT" ] && command -v sbsign >/dev/null 2>&1; then
    echo "POST-IMAGE: Keys verified. Signing binaries..."
    
    # Sign GRUB and the Linux Kernel with your private keys so Shim authorizes them
    sbsign --key "$SB_KEY" --cert "$SB_CRT" --output "${EFI_DIR}/grubx64.efi" "${EFI_DIR}/grubx64.efi"
    sbsign --key "$SB_KEY" --cert "$SB_CRT" --output "${BINARIES_DIR}/efi-part/bzImage" "${BINARIES_DIR}/bzImage"
    
    echo "POST-IMAGE: Cryptographic validation completed."
else
    echo "POST-IMAGE: WARNING: Secure Boot keys or sbsign tool missing! Packing unsigned payloads."
    cp "${BINARIES_DIR}/bzImage" "${BINARIES_DIR}/efi-part/bzImage"
fi

echo "POST-IMAGE: Executing genimage configuration wrapper..."
support/scripts/genimage.sh "$@"
