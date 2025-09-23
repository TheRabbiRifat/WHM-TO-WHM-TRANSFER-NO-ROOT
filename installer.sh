#!/usr/bin/env bash
# WHM Source Scanner - List Packages and Accounts (No Root)
# Usage: sudo bash -c "$(curl -fsSL <URL> || wget -qO- <URL>)"

set -euo pipefail
IFS=$'\n\t'

# --- Colors ---
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

# --- Banner ---
echo -e "${CYAN}==============================================${RESET}"
echo -e "${CYAN}   WHM Source Scanner - Packages & Accounts   ${RESET}"
echo -e "${CYAN}==============================================${RESET}"
echo

# --- Install jq if missing ---
if ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}[*] jq not found. Installing jq...${RESET}"
    if command -v yum &>/dev/null; then
        sudo yum install -y jq
    elif command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y jq
    else
        echo -e "${RED}ERROR: Could not install jq. Please install it manually.${RESET}"
        exit 1
    fi
fi

# --- Input source WHM credentials ---
read -p "Enter source WHM hostname: " SRC_HOST
read -p "Enter source WHM username: " SRC_USER
read -sp "Enter source WHM password: " SRC_PASS
echo

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
echo -e "${CYAN}[*] Fetching all packages from $SRC_HOST...${RESET}"
PACKAGES_JSON=$(whm_api "$SRC_HOST" "$SRC_USER" "$SRC_PASS" "listpkgs" "")
PACKAGES=$(echo "$PACKAGES_JSON" | jq -r '.data.pkg[]?.name // empty')

if [[ -z "$PACKAGES" ]]; then
    echo -e "${YELLOW} - No packages found or insufficient permissions.${RESET}"
else
    echo -e "${GREEN}[*] Found packages:${RESET}"
    while IFS= read -r pkg; do
        echo -e " - $pkg"
    done <<< "$PACKAGES"
fi

# --- Step 2: List all accounts/users ---
echo -e "${CYAN}[*] Fetching all accounts/users under this reseller...${RESET}"
ACCOUNTS_JSON=$(whm_api "$SRC_HOST" "$SRC_USER" "$SRC_PASS" "listaccts" "")
ACCOUNTS=$(echo "$ACCOUNTS_JSON" | jq -r '.data.accts[]?.user // empty')

if [[ -z "$ACCOUNTS" ]]; then
    echo -e "${YELLOW} - No accounts found or insufficient permissions.${RESET}"
else
    echo -e "${GREEN}[*] Found accounts/users:${RESET}"
    while IFS= read -r user; do
        echo -e " - $user"
    done <<< "$ACCOUNTS"
fi

echo -e "${CYAN}\n[*] Done. All packages and users listed successfully.${RESET}"
