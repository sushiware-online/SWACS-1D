#!/bin/bash
set -e

# Buildroot variables
BINARIES_DIR="$1"
BOARD_DIR="board/swacs1d"
EFI_DIR="${BINARIES_DIR}/efi-part/EFI/BOOT"

echo "POST-IMAGE: Preparing Secure Boot EFI directory structure..."

# Clear out any old configuration debris and rebuild clean folders
rm -rf "${BINARIES_DIR}/efi-part"
mkdir -p "${EFI_DIR}"

# 1. Verify build deliverables exist
if [ ! -f "${BINARIES_DIR}/shimx64.efi" ]; then
    echo "ERROR: shimx64.efi not found in ${BINARIES_DIR}! Check BR2_PACKAGE_SHIM."
    exit 1
fi

if [ ! -f "${BINARIES_DIR}/grub.efi" ]; then
    echo "ERROR: grub.efi not found in ${BINARIES_DIR}! Check BR2_TARGET_GRUB2."
    exit 1
fi

# 2. Setup staging targets
# Shim becomes the fallback primary target standard UEFI platforms seek out
cp "${BINARIES_DIR}/shimx64.efi" "${EFI_DIR}/BOOTX64.EFI"
# Clean copy of Grub stored exactly where Shim looks to forward validation execution
cp "${BINARIES_DIR}/grub.efi" "${EFI_DIR}/grubx64.efi"
# Copy configuration profile
cp "${BOARD_DIR}/grub.cfg" "${EFI_DIR}/grub.cfg"

# 3. Handle Binary Code Signing Operations
SB_KEY="${BOARD_DIR}/keys/db.key"
SB_CRT="${BOARD_DIR}/keys/db.crt"

if [ -f "$SB_KEY" ] && [ -f "$SB_CRT" ] && command -v sbsign >/dev/null 2>&1; then
    echo "POST-IMAGE: Secure Boot keys found. Signing binaries..."
    
    # Note: Shim itself shouldn't be signed by your DB key (it's typically signed by MS or left as-is depending on your PK deployment)
    # But GRUB and your kernel MUST be signed by your DB key so Shim accepts them!
    sbsign --key "$SB_KEY" --cert "$SB_CRT" --output "${EFI_DIR}/grubx64.efi" "${EFI_DIR}/grubx64.efi"
    sbsign --key "$SB_KEY" --cert "$SB_CRT" --output "${BINARIES_DIR}/efi-part/bzImage" "${BINARIES_DIR}/bzImage"
    
    echo "POST-IMAGE: Verification Signatures generated cleanly."
else
    echo "POST-IMAGE: WARNING: Secure Boot keys or sbsign tool missing! Copying unsigned kernels."
    cp "${BINARIES_DIR}/bzImage" "${BINARIES_DIR}/efi-part/bzImage"
fi

echo "POST-IMAGE: Running genimage to pack the target filesystem image..."
