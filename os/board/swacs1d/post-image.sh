#!/bin/bash
set -e

# Buildroot variables
BINARIES_DIR="$1"
BOARD_DIR="board/swacs1d"
EFI_DIR="${BINARIES_DIR}/efi-part/EFI/BOOT"

echo "POST-IMAGE: Preparing Custom Shim + Grub Secure Boot structure..."

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
mkdir -p "${EFI_DIR}"

# Step A: Move the default Grub binary out of the way first, under the filename Shim expects
mv "${ORIG_GRUB}" "${EFI_DIR}/grubx64.efi"

# Step B: Copy the verified Shim source into the primary UEFI fall-through position (BOOTX64.EFI)
cp "${SHIM_SRC}" "${EFI_DIR}/BOOTX64.EFI"

# Step C: Pull custom Grub target menus over
if [ -f "${BOARD_DIR}/grub.cfg" ]; then
    cp "${BOARD_DIR}/grub.cfg" "${EFI_DIR}/grub.cfg"
else
    echo "WARNING: ${BOARD_DIR}/grub.cfg not found, keeping default Buildroot grub.cfg if present."
fi

# 4. Handle Cryptographic Code Signing Routines
SHIM_KEY="${BOARD_DIR}/keys/shim.key"
SHIM_CRT="${BOARD_DIR}/keys/shim.crt"

DB_KEY="${BOARD_DIR}/keys/db.key"
DB_CRT="${BOARD_DIR}/keys/db.crt"

# Always stage the kernel image to the target partition first
cp "${BINARIES_DIR}/bzImage" "${BINARIES_DIR}/efi-part/bzImage"

if command -v sbsign >/dev/null 2>&1; then
    echo "POST-IMAGE: sbsign tool discovered. Checking keys..."
    
    # Sign Shim (BOOTX64.EFI) using the separate, dedicated Shim keys
    if [ -f "$SHIM_KEY" ] && [ -f "$SHIM_CRT" ]; then
        echo "POST-IMAGE: Signing BOOTX64.EFI (Shim) with dedicated Shim keys..."
        sbsign --key "$SHIM_KEY" --cert "$SHIM_CRT" --output "${EFI_DIR}/BOOTX64.EFI" "${EFI_DIR}/BOOTX64.EFI"
    else
        echo "POST-IMAGE: WARNING: Dedicated Shim keys missing. BOOTX64.EFI left unsigned."
    fi

    # Sign GRUB and your kernel with your downstream standard DB keys
    if [ -f "$DB_KEY" ] && [ -f "$DB_CRT" ]; then
        echo "POST-IMAGE: Signing grubx64.efi and bzImage with DB keys..."
        sbsign --key "$DB_KEY" --cert "$DB_CRT" --output "${EFI_DIR}/grubx64.efi" "${EFI_DIR}/grubx64.efi"
        sbsign --key "$DB_KEY" --cert "$DB_CRT" --output "${BINARIES_DIR}/efi-part/bzImage" "${BINARIES_DIR}/efi-part/bzImage"
    else
        echo "POST-IMAGE: WARNING: DB keys missing. GRUB and Kernel left unsigned."
    fi
    
    echo "POST-IMAGE: Cryptographic validation steps completed."
else
    echo "POST-IMAGE: WARNING: sbsign tool missing! Packaging unsigned files."
fi

echo "POST-IMAGE: Formatting system image partitions via genimage wrapper..."
support/scripts/genimage.sh "$@"