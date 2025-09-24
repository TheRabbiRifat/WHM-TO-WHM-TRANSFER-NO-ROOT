#!/usr/bin/env bash
# WHM Packages & cPanel Account Sync
# Auth: WHM API Token (Authorization: whm user:token)
# Usage: sudo bash -c "$(curl -fsSL <RAW_URL> || wget -qO- <RAW_URL>)"
set -euo pipefail
IFS=$'\n\t'

# Colors
GREEN="\e[32m"; CYAN="\e[36m"; YELLOW="\e[33m"; RED="\e[31m"; RESET="\e[0m"

echo -e "${CYAN}==============================================${RESET}"
echo -e "${CYAN} WHM Packages & Accounts Sync Script ${RESET}"
echo -e "${CYAN}==============================================${RESET}"
echo

# Ensure jq exists
if ! command -v jq &>/dev/null; then
  echo -e "${YELLOW}[*] Installing jq...${RESET}"
  if command -v yum &>/dev/null; then sudo yum install -y jq
  elif command -v apt &>/dev/null; then sudo apt update && sudo apt install -y jq
  else echo -e "${RED}[!] Cannot install jq automatically.${RESET}"; exit 1; fi
fi

# --- Credentials ---
read -p "Source WHM host (no https://): " SRC_HOST
read -p "Source WHM username: " SRC_USER
read -sp "Source WHM API token: " SRC_TOKEN
echo
read -p "Destination WHM host (no https://): " DST_HOST
read -p "Destination WHM username: " DST_USER
read -sp "Destination WHM API token: " DST_TOKEN
echo

read -p "Dry-run mode? (y/N): " DRYRUN
DRYRUN=${DRYRUN,,}

# Helpers
step() { echo -e "${CYAN}[STEP]${RESET} $*"; }
ok() { echo -e "${GREEN}[OK]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
err() { echo -e "${RED}[ERR]${RESET} $*"; }

whm_api() {
  local host="$1"; local user="$2"; local token="$3"; local endpoint="$4"; local params="$5"
  [[ -z "$params" ]] && params="api.version=1" || params="${params}&api.version=1"
  local resp
  if ! resp=$(curl -s -k -H "Authorization: whm ${user}:${token}" "https://${host}:2087/json-api/${endpoint}?${params}" 2>/dev/null); then
    err "Cannot connect to WHM API at $host"
    exit 1
  fi
  echo "$resp"
}

# --- 1) Fetch source packages ---
step "Fetching packages from source..."
PKG_JSON=$(whm_api "$SRC_HOST" "$SRC_USER" "$SRC_TOKEN" "listpkgs" "")
PKG_NAMES=$(echo "$PKG_JSON" | jq -r '.data.pkg[]?.name // empty' | sed '/^$/d' || true)

[[ -z "$PKG_NAMES" ]] && {
  warn "No packages found via listpkgs, trying listaccts..."
  ACC_JSON=$(whm_api "$SRC_HOST" "$SRC_USER" "$SRC_TOKEN" "listaccts" "")
  PKG_NAMES=$(echo "$ACC_JSON" | jq -r '
    if .data.acct != null then
      .data.acct[] | (.plan // .pkg // .plan_name // empty)
    elif .data.accts != null then
      .data.accts[] | (.plan // .pkg // .plan_name // empty)
    else empty end
  ' | sort -u | sed '/^$/d')
}

echo -e "${CYAN}Source Packages:${RESET}"
[[ -z "$PKG_NAMES" ]] && echo -e "${YELLOW} (none found)${RESET}" || echo "$PKG_NAMES" | sed 's/^/ - /'
[[ -z "$PKG_NAMES" ]] && { warn "No packages to create."; exit 0; }

# --- 2) Fetch destination packages ---
step "Fetching destination packages..."
DST_PKG_JSON=$(whm_api "$DST_HOST" "$DST_USER" "$DST_TOKEN" "listpkgs" "")
DST_PKG_NAMES=$(echo "$DST_PKG_JSON" | jq -r '.data.pkg[]?.name // empty')

# --- 3) Create missing packages ---
for pkg in $PKG_NAMES; do
  step "Processing package $pkg"
  if echo "$DST_PKG_NAMES" | grep -Fxq "$pkg"; then
    ok "Package '$pkg' exists on destination, skipping."
    continue
  fi

  # fetch config
  PKGINFO_JSON=$(whm_api "$SRC_HOST" "$SRC_USER" "$SRC_TOKEN" "getpkginfo" "pkg=$(jq -s -R -r @uri <<<"$pkg")" || true)
  RESULT_OK=$(echo "$PKGINFO_JSON" | jq -r '.metadata.result // "0"')

  if [[ "$RESULT_OK" != "1" ]]; then
    warn "Cannot get details for $pkg, using fallback 30 values."
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

  echo -e "${CYAN}Package to create:$RESET $pkg (quota=$quota, bandwidth=$bandwidth)"
  if [[ "$DRYRUN" == "y" ]]; then
    warn "[DRY-RUN] Would create package $pkg"
    continue
  fi

  # Build addpkg params
  ADDPKG_PARAMS="name=$(jq -s -R -r @uri <<<"$pkg")&quota=$quota&bandwidth=$bandwidth&maxftp=$maxftp&maxsql=$maxsql&maxpop=$maxpop&maxlst=$maxlst&maxpark=$maxpark&maxaddon=$maxaddon&maxsub=$maxsub&hasshell=$hasshell&featurelist=$featurelist&ip=$ip"
  [[ -n "$language" ]] && ADDPKG_PARAMS+="&language=$(jq -s -R -r @uri <<<"$language")"
  [[ -n "$cpmod" ]] && ADDPKG_PARAMS+="&cpmod=$(jq -s -R -r @uri <<<"$cpmod")"

  ADDPKG_RESP=$(whm_api "$DST_HOST" "$DST_USER" "$DST_TOKEN" "addpkg" "$ADDPKG_PARAMS" || true)
  SUCCESS=$(echo "$ADDPKG_RESP" | jq -r '.metadata.result // "0"')
  [[ "$SUCCESS" == "1" ]] && ok "Package $pkg created." || warn "Failed to create package $pkg."
done

# --- 4) Fetch source cPanel accounts ---
step "Fetching source accounts..."
ACCT_JSON=$(whm_api "$SRC_HOST" "$SRC_USER" "$SRC_TOKEN" "listaccts" "")
ACCT_USERS=$(echo "$ACCT_JSON" | jq -r '.data.acct[]?.user // .data.accts[]?.user // empty' | sed '/^$/d')

echo -e "${CYAN}Accounts on source:$RESET"
echo "$ACCT_USERS" | sed 's/^/ - /'

# --- 5) Create missing accounts ---
for user in $ACCT_USERS; do
  step "Processing account $user"

  # fetch package assigned to account
  pkg=$(echo "$ACCT_JSON" | jq -r --arg u "$user" '.data.acct[]? | select(.user==$u) | .plan // empty')
  [[ -z "$pkg" ]] && pkg="default"

  # generate dummy password
  PASS=$(openssl rand -base64 12)

  if [[ "$DRYRUN" == "y" ]]; then
    warn "[DRY-RUN] Would create cPanel account $user with package $pkg and dummy password $PASS"
    continue
  fi

  step "Creating cPanel account $user on destination..."
  ADDACCT_PARAMS="username=$(jq -s -R -r @uri <<<"$user")&domain=$(jq -s -R -r @uri <<<"$user").example.com&password=$(jq -s -R -r @uri <<<"$PASS")&plan=$(jq -s -R -r @uri <<<"$pkg")&contactemail=$(jq -s -R -r @uri <<<"$user")@example.com"

  ADDACCT_RESP=$(whm_api "$DST_HOST" "$DST_USER" "$DST_TOKEN" "createacct" "$ADDACCT_PARAMS" || true)
  SUCCESS=$(echo "$ADDACCT_RESP" | jq -r '.metadata.result // "0"')
  [[ "$SUCCESS" == "1" ]] && ok "Account $user created." || warn "Failed to create account $user."
done

echo
ok "All done! Dry-run=${DRYRUN:-N}"
