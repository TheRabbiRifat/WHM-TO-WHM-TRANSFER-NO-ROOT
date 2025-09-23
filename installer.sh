#!/usr/bin/env bash
# WHM-to-WHM Transfer (No Root)
# Single-file installer/script (no jq required)
# Usage: sudo bash -c "$(curl -fsSL <URL> || wget -qO- <URL>)"

set -euo pipefail
IFS=$'\n\t'

# --- Banner ---
echo "=============================================="
echo "   WHM-to-WHM Transfer (No Root) Script       "
echo "=============================================="
echo

# --- Input source WHM credentials ---
read -p "Enter source WHM hostname: " SRC_HOST
read -p "Enter source WHM username: " SRC_USER
read -sp "Enter source WHM password: " SRC_PASS
echo

# --- Optional: Destination credentials ---
read -p "Enter destination hostname (FTP target or WHM host, optional): " DST_HOST
read -p "Enter destination username (optional): " DST_USER
read -sp "Enter destination password (optional): " DST_PASS
echo
read -p "Enter destination FTP path (default /, optional): " DST_DIR
DST_DIR=${DST_DIR:-/}

# --- WHM API function ---
whm_api() {
    local host="$1"
    local user="$2"
    local pass="$3"
    local endpoint="$4"
    local params="$5"

    curl -s -k -u "${user}:${pass}" "https://${host}:2087/json-api/${endpoint}?${params}"
}

# --- Step 1: List all packages ---
echo "[*] Fetching all packages from $SRC_HOST..."
PACKAGES_JSON=$(whm_api "$SRC_HOST" "$SRC_USER" "$SRC_PASS" "listpkgs" "")

# Extract "name":"PACKAGE_NAME" properly
PACKAGES=$(echo "$PACKAGES_JSON" | tr -d '\n' | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//')

echo "[*] Found packages:"
if [[ -z "$PACKAGES" ]]; then
    echo " - No packages found or insufficient permissions."
else
    while IFS= read -r pkg; do
        echo " - $pkg"
    done <<< "$PACKAGES"
fi

# --- Step 2: List all accounts/users ---
echo "[*] Fetching all accounts/users under this reseller..."
ACCOUNTS_JSON=$(whm_api "$SRC_HOST" "$SRC_USER" "$SRC_PASS" "listaccts" "")

# Extract usernames properly
ACCOUNTS=$(echo "$ACCOUNTS_JSON" | tr -d '\n' | grep -o '"user":"[^"]*"' | sed 's/"user":"//;s/"//')

echo "[*] Found accounts/users:"
if [[ -z "$ACCOUNTS" ]]; then
    echo " - No accounts found or insufficient permissions."
else
    while IFS= read -r user; do
        echo " - $user"
    done <<< "$ACCOUNTS"
fi

echo
echo "[*] Done. All packages and users listed successfully."
