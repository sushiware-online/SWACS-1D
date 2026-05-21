#!/bin/bash
# Generate testing keys for SWACS-1D provisioning and update bundles
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "Generating private RSA key..."
openssl genrsa -out update_private.pem 2048

echo "Extracting public RSA key..."
openssl rsa -pubout -in update_private.pem -out update_public.pem

echo "Creating AES key with 0000 password..."
echo -n "0000" > update_aes.key

# Generate UEFI Secure Boot keys hierarchy (PK, KEK, db)
SB_KEYS_DIR="../os/board/swacs1d/keys"
mkdir -p "$SB_KEYS_DIR"

# 1. Generate Signature Database (db) - Used to sign the OS binaries
if [ ! -f "$SB_KEYS_DIR/db.key" ]; then
    echo "Generating UEFI Secure Boot DB keys..."
    openssl req -new -x509 -newkey rsa:2048 -nodes -keyout "$SB_KEYS_DIR/db.key" -out "$SB_KEYS_DIR/db.crt" -days 3650 -subj "/CN=SWACS Secure Boot DB/"
    openssl x509 -in "$SB_KEYS_DIR/db.crt" -outform DER -out "$SB_KEYS_DIR/db.der"
fi

# 2. Generate Key Exchange Key (KEK) - Authorizes changes to db/dbx
if [ ! -f "$SB_KEYS_DIR/KEK.key" ]; then
    echo "Generating UEFI Secure Boot KEK keys..."
    openssl req -new -x509 -newkey rsa:2048 -nodes -keyout "$SB_KEYS_DIR/KEK.key" -out "$SB_KEYS_DIR/KEK.crt" -days 3650 -subj "/CN=SWACS Secure Boot KEK/"
    openssl x509 -in "$SB_KEYS_DIR/KEK.crt" -outform DER -out "$SB_KEYS_DIR/KEK.der"
fi

# 3. Generate Platform Key (PK) - The hardware master/owner key
if [ ! -f "$SB_KEYS_DIR/PK.key" ]; then
    echo "Generating UEFI Secure Boot PK keys..."
    openssl req -new -x509 -newkey rsa:2048 -nodes -keyout "$SB_KEYS_DIR/PK.key" -out "$SB_KEYS_DIR/PK.crt" -days 3650 -subj "/CN=SWACS Secure Boot PK/"
    openssl x509 -in "$SB_KEYS_DIR/PK.crt" -outform DER -out "$SB_KEYS_DIR/PK.der"
fi

echo "Keys initialized successfully!"