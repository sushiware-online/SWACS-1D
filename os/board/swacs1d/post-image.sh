#!/bin/bash
set -e

# Buildroot variables
BINARIES_DIR="$1"
BOARD_DIR="board/swacs1d"
EFI_DIR="${BINARIES_DIR}/efi-part/EFI/BOOT"

# Dynamically compute Buildroot base directory locations safely
BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT_DIR="${BINARIES_DIR}/.."
TARGET_DIR="${OUTPUT_DIR}/target"
BUILD_DIR="${OUTPUT_DIR}/build"

echo "POST-IMAGE: Preparing Secure Boot EFI directory structure..."

# Clear out any old configuration debris and rebuild clean folders
rm -rf "${BINARIES_DIR}/efi-part"
mkdir -p "${EFI_DIR}"

# 1. Broad Lookup Matrix for shimx64.efi
SHIM_SRC=""
if [ -f "${BINARIES_DIR}/shimx64.efi" ]; then
    SHIM_SRC="${BINARIES_DIR}/shimx64.efi"
elif [ -f "${TARGET_DIR}/usr/lib/shim/shimx64.efi" ]; then
    SHIM_SRC="${TARGET_DIR}/usr/lib/shim/shimx64.efi"
elif [ -f "${TARGET_DIR}/boot/shimx64.efi" ]; then
    SHIM_SRC="${TARGET_DIR}/boot/shimx64.efi"
else
    # CI/CD Failover: Search inside the compiled build package direct tree space
    SHIM_FIND=$(find "${BUILD_DIR}" -type f -name "shimx64.efi" | head -n 1)
    if [ -n "${SHIM_FIND}" ] && [ -f "${SHIM_FIND}" ]; then
        SHIM_SRC="${SHIM_FIND}"
    fi
fi

# Sanity Check
if [ -z "${SHIM_SRC}" ] || [ ! -f "${SHIM_SRC}" ]; then
    echo "ERROR: shimx64.efi could not be located anywhere in image, target, or build subtrees!"
    echo "Diagnostic: Contents of ${BINARIES_DIR}:"
    ls -la "${BINARIES_DIR}"
    exit 1
else
    echo "POST-IMAGE: Found shim target source path at: ${SHIM_SRC}"
fi

if [ ! -f "${BINARIES_DIR}/grub.efi" ]; then
    echo "ERROR: grub.efi not found in ${BINARIES_DIR}! Check BR2_TARGET_GRUB2."
    exit 1
fi

# 2. Setup staging targets
cp "${SHIM_SRC}" "${EFI_DIR}/BOOTX64.EFI"
cp "${BINARIES_DIR}/grub.efi" "${EFI_DIR}/grubx64.efi"
cp "${BOARD_DIR}/grub.cfg" "${EFI_DIR}/grub.cfg"

# 3. Handle Binary Code Signing Operations
SB_KEY="${BOARD_DIR}/keys/db.key"
SB_CRT="${BOARD_DIR}/keys/db.crt"

if [ -f "$SB_KEY" ] && [ -f "$SB_CRT" ] && command -v sbsign >/dev/null 2>&1; then
    echo "POST-IMAGE: Secure Boot keys found. Signing binaries..."
    sbsign --key "$SB_KEY" --cert "$SB_CRT" --output "${EFI_DIR}/grubx64.efi" "${EFI_DIR}/grubx64.efi"
    
    # Ensure staging sub-directory for bzImage copy path exists
    mkdir -p "${BINARIES_DIR}/efi-part"
    sbsign --key "$SB_KEY" --cert "$SB_CRT" --output "${BINARIES_DIR}/efi-part/bzImage" "${BINARIES_DIR}/bzImage"
    
    echo "POST-IMAGE: Verification Signatures generated cleanly."
else
    echo "POST-IMAGE: WARNING: Secure Boot keys or sbsign tool missing! Copying unsigned kernels."
    mkdir -p "${BINARIES_DIR}/efi-part"
    cp "${BINARIES_DIR}/bzImage" "${BINARIES_DIR}/efi-part/bzImage"
fi

echo "POST-IMAGE: Running genimage helper to pack target..."
support/scripts/genimage.sh "$@"
