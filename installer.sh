#!/usr/bin/env bash
# installer.sh
# Fetch packages from source WHM and create missing packages on destination WHM
# Auth: WHM API Token (Authorization: whm user:token)
#
# Usage:
# sudo bash -c "$(curl -fsSL <RAW_URL> || wget -qO- <RAW_URL>)"
#
set -euo pipefail
IFS=$'\n\t'

# Colors
GREEN="\e[32m"; CYAN="\e[36m"; YELLOW="\e[33m"; RED="\e[31m"; RESET="\e[0m"

echo -e "${CYAN}==============================================${RESET}"
echo -e "${CYAN} WHM Packages Sync — Fetch from source & create on destination ${RESET}"
echo -e "${CYAN}==============================================${RESET}"
echo

# Ensure jq exists
if ! command -v jq &>/dev/null; then
  echo -e "${YELLOW}[*] 'jq' not found. Attempting to install...${RESET}"
  if command -v yum &>/dev/null; then
    sudo yum install -y jq
  elif command -v apt &>/dev/null; then
    sudo apt update && sudo apt install -y jq
  else
    echo -e "${RED}[!] Could not install jq automatically. Please install jq and re-run.${RESET}"
    exit 1
  fi
fi

# --- Prompt for credentials ---
read -p "Source WHM hostname (no https://, e.g. whm.example.com): " SRC_HOST
read -p "Source WHM username (root or reseller): " SRC_USER
read -sp "Source WHM API token: " SRC_TOKEN
echo
echo

read -p "Destination WHM hostname (no https://): " DST_HOST
read -p "Destination WHM username (root or reseller): " DST_USER
read -sp "Destination WHM API token: " DST_TOKEN
echo
echo

# Helpers
step() { echo -e "${CYAN}[STEP]${RESET} $*"; }
ok()   { echo -e "${GREEN}[OK]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
err()  { echo -e "${RED}[ERR]${RESET} $*"; }

# Wrapper for WHM API call with error handling
whm_api_token() {
  local host="$1" user="$2" token="$3" endpoint="$4" params="$5"
  [[ -z "$params" ]] && params="api.version=1" || params="${params}&api.version=1"

  local resp
  if ! resp=$(curl -s -k -H "Authorization: whm ${user}:${token}" \
    "https://${host}:2087/json-api/${endpoint}?${params}" 2>/dev/null); then
    err "Unable to connect to WHM API at ${host}"
    exit 1
  fi

  # Check metadata for errors
  local result reason
  result=$(echo "$resp" | jq -r '.metadata.result // empty')
  reason=$(echo "$resp" | jq -r '.metadata.reason // empty')
  if [[ "$result" == "0" || "$result" == "null" ]]; then
    err "API call '${endpoint}' failed: ${reason:-Unknown error}"
    exit 1
  fi

  echo "$resp"
}

# --- 1) Query source WHM packages ---
step "Querying source WHM for packages..."
PKG_JSON=$(whm_api_token "$SRC_HOST" "$SRC_USER" "$SRC_TOKEN" "listpkgs" "")
PKG_NAMES=$(echo "$PKG_JSON" | jq -r '.data.pkg[]?.name // empty' | sed '/^$/d' || true)

if [[ -z "$PKG_NAMES" ]]; then
  warn "No packages returned by listpkgs. Trying listaccts..."
  ACC_JSON=$(whm_api_token "$SRC_HOST" "$SRC_USER" "$SRC_TOKEN" "listaccts" "")
  PKG_NAMES=$(echo "$ACC_JSON" | jq -r '
    if .data.acct != null then
      .data.acct[] | (.plan // .pkg // .plan_name // empty)
    elif .data.accts != null then
      .data.accts[] | (.plan // .pkg // .plan_name // empty)
    else empty end
  ' | sort -u | sed '/^$/d')
fi

echo
echo -e "${CYAN}=== Packages discovered on source (${SRC_HOST}) ===${RESET}"
[[ -z "$PKG_NAMES" ]] && echo -e "${YELLOW} (none found)${RESET}" || echo "$PKG_NAMES" | sed 's/^/ - /'
[[ -z "$PKG_NAMES" ]] && { warn "Nothing to do."; exit 0; }
echo

# --- 2) Get destination packages ---
step "Fetching existing destination packages..."
DST_PKG_JSON=$(whm_api_token "$DST_HOST" "$DST_USER" "$DST_TOKEN" "listpkgs" "")
DST_PKG_NAMES=$(echo "$DST_PKG_JSON" | jq -r '.data.pkg[]?.name // empty')
ok "Destination already has $(echo "$DST_PKG_NAMES" | wc -l) package(s)."

# --- 3) Loop through source packages ---
for pkg in $PKG_NAMES; do
  echo
  step "Processing package: $pkg"

  if echo "$DST_PKG_NAMES" | grep -Fxq "$pkg"; then
    ok "Package '$pkg' already exists on destination. Skipping."
    continue
  fi

  step "Fetching details for '$pkg'..."
  PKGINFO_JSON=$(whm_api_token "$SRC_HOST" "$SRC_USER" "$SRC_TOKEN" "getpkginfo" "pkg=$(jq -s -R -r @uri <<<"$pkg")" || true)
  RESULT_OK=$(echo "$PKGINFO_JSON" | jq -r '.metadata.result // "0"')

  if [[ "$RESULT_OK" != "1" ]]; then
    warn "Could not get details for '$pkg'. Using fallback (30 values)."
    quota=30; bandwidth=30; maxftp=30; maxsql=30; maxpop=30; maxlst=30; maxpark=30; maxaddon=30; maxsub=30
    hasshell=0; featurelist=default; language=""; cpmod=""; ip="n"
  else
    quota=$(echo "$PKGINFO_JSON" | jq -r '.data.pkg.quota // "30"')
    bandwidth=$(echo "$PKGINFO_JSON" | jq -r '.data.pkg.bandwidth // "30"')
    maxftp=$(echo "$PKGINFO_JSON" | jq -r '.data.pkg.maxftp // "30"')
    maxsql=$(echo "$PKGINFO_JSON" | jq -r '.data.pkg.maxsql // "30"')
    maxpop=$(echo "$PKGINFO_JSON" | jq -r '.data.pkg.maxpop // "30"')
    maxlst=$(echo "$PKGINFO_JSON" | jq -r '.data.pkg.maxlst // "30"')
    maxpark=$(echo "$PKGINFO_JSON" | jq -r '.data.pkg.maxpark // "30"')
    maxaddon=$(echo "$PKGINFO_JSON" | jq -r '.data.pkg.maxaddon // "30"')
    maxsub=$(echo "$PKGINFO_JSON" | jq -r '.data.pkg.maxsub // "30"')
    hasshell=$(echo "$PKGINFO_JSON" | jq -r '.data.pkg.hasshell // "0"')
    featurelist=$(echo "$PKGINFO_JSON" | jq -r '.data.pkg.featurelist // "default"')
    language=$(echo "$PKGINFO_JSON" | jq -r '.data.pkg.language // empty')
    cpmod=$(echo "$PKGINFO_JSON" | jq -r '.data.pkg.cpmod // empty')
    ip=$(echo "$PKGINFO_JSON" | jq -r '.data.pkg.ip // "n"')
  fi

  echo -e "${CYAN}→ Creating with:${RESET} quota=$quota, bw=$bandwidth, ftp=$maxftp, sql=$maxsql"

  step "Creating package on destination..."
  ADDPKG_PARAMS="name=$(jq -s -R -r @uri <<<"$pkg")&quota=$quota&bandwidth=$bandwidth&maxftp=$maxftp&maxsql=$maxsql&maxpop=$maxpop&maxlst=$maxlst&maxpark=$maxpark&maxaddon=$maxaddon&maxsub=$maxsub&hasshell=$hasshell&featurelist=$featurelist&ip=$ip"
  [[ -n "$language" ]] && ADDPKG_PARAMS+="&language=$(jq -s -R -r @uri <<<"$language")"
  [[ -n "$cpmod" ]] && ADDPKG_PARAMS+="&cpmod=$(jq -s -R -r @uri <<<"$cpmod")"

  ADDPKG_RESP=$(whm_api_token "$DST_HOST" "$DST_USER" "$DST_TOKEN" "addpkg" "$ADDPKG_PARAMS" || true)
  SUCCESS=$(echo "$ADDPKG_RESP" | jq -r '.metadata.result // "0"')

  if [[ "$SUCCESS" == "1" ]]; then
    ok "Created package '$pkg' on destination."
  else
    REASON=$(echo "$ADDPKG_RESP" | jq -r '.metadata.reason // "unknown"')
    err "Failed to create '$pkg'. Reason: $REASON"
    echo "$ADDPKG_RESP" | jq .
  fi
done

echo
ok "Sync complete."
