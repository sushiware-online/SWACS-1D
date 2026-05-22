#!/bin/bash
set -e

# Buildroot variables
BINARIES_DIR="$1"
BOARD_DIR="board/swacs1d"
EFI_DIR="${BINARIES_DIR}/efi-part/EFI/BOOT"

echo "POST-IMAGE: Preparing Custom Shim + Grub Secure Boot structure..."

# Create clean execution targets
mkdir -p "${EFI_DIR}"
mkdir -p "${BINARIES_DIR}/efi-part"

# 1. Locate Shim inside Buildroot's core images directory
SHIM_SRC=""
if [ -f "${BINARIES_DIR}/shim.efi" ]; then
    SHIM_SRC="${BINARIES_DIR}/shim.efi"
elif [ -f "${BINARIES_DIR}/shimx64.efi" ]; then
    SHIM_SRC="${BINARIES_DIR}/shimx64.efi"
else
    echo "ERROR: Neither shim.efi nor shimx64.efi was found in ${BINARIES_DIR}!"
    echo "Double-check your defconfig contains: BR2_TARGET_SHIM=y"
    exit 1
fi

echo "POST-IMAGE: Located valid Shim binary at: ${SHIM_SRC}"

# 2. Verify Grub exists (Buildroot automatically generates it here)
ORIG_GRUB="${BINARIES_DIR}/efi-part/EFI/BOOT/bootx64.efi"
if [ ! -f "${ORIG_GRUB}" ]; then
    echo "ERROR: Original Grub binary not found at ${ORIG_GRUB}!"
    exit 1
fi

# 3. Arrange filesystem files to map standard UEFI Shim execution layouts
# Copy the verified Shim source into the primary fall-through load position
cp "${SHIM_SRC}" "${EFI_DIR}/BOOTX64.EFI"

# Move the default Grub binary right beside it under the filename Shim expects
mv "${ORIG_GRUB}" "${EFI_DIR}/grubx64.efi"

# Pull custom Grub target menus over
cp "${BOARD_DIR}/grub.cfg" "${EFI_DIR}/grub.cfg"

# 4. Handle Cryptographic Code Signing Routines
SB_KEY="${BOARD_DIR}/keys/db.key"
SB_CRT="${BOARD_DIR}/keys/db.crt"

if [ -f "$SB_KEY" ] && [ -f "$SB_CRT" ] && command -v sbsign >/dev/null 2>&1; then
    echo "POST-IMAGE: Verification keys discovered. Signing runtime binaries..."
    
    # Sign GRUB and your kernel with your platform keys so Shim authorizes them at boot
    sbsign --key "$SB_KEY" --cert "$SB_CRT" --output "${EFI_DIR}/grubx64.efi" "${EFI_DIR}/grubx64.efi"
    sbsign --key "$SB_KEY" --cert "$SB_CRT" --output "${BINARIES_DIR}/efi-part/bzImage" "${BINARIES_DIR}/bzImage"
    
    echo "POST-IMAGE: Cryptographic validation steps completed safely."
else
    echo "POST-IMAGE: WARNING: Secure Boot signing keys or sbsign tool missing! Packaging unsigned files."
    cp "${BINARIES_DIR}/bzImage" "${BINARIES_DIR}/efi-part/bzImage"
fi

echo "POST-IMAGE: Formatting system image partitions via genimage wrapper..."
support/scripts/genimage.sh "$@"
