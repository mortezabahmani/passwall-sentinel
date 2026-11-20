#!/bin/sh
# passwall-sentinel - Universal Single-Command Installer
# Compatible with OpenWrt 25.x+ (apk) and OpenWrt 19.x - 24.x (opkg)
# No compilation required (Universal Architecture: arm, aarch64, mips, x86_64)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}       passwall-sentinel Installation Script         ${NC}"
echo -e "${BLUE}======================================================${NC}"

# Default GitHub Raw URL
PWS_RAW_URL="${PWS_RAW_URL:-https://raw.githubusercontent.com/mortezabahmani/passwall-sentinel/main}"

# 1. Detect Package Manager
PKG_MGR=""
if command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    echo -e "${GREEN}[+] Detected modern OpenWrt package manager: apk${NC}"
elif command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
    echo -e "${GREEN}[+] Detected standard OpenWrt package manager: opkg${NC}"
else
    echo -e "${RED}[!] Error: Neither apk nor opkg found!${NC}"
    exit 1
fi

# 2. Check & Install Dependencies
echo -e "${BLUE}[+] Checking runtime dependencies...${NC}"
MISSING_PKGS=""
for pkg in curl tcping; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
        MISSING_PKGS="$MISSING_PKGS $pkg"
    fi
done

if [ -n "$MISSING_PKGS" ]; then
    echo -e "${YELLOW}[*] Installing missing dependencies:${MISSING_PKGS}...${NC}"
    if [ "$PKG_MGR" = "apk" ]; then
        apk update || true
        apk add $MISSING_PKGS || true
    else
        opkg update || true
        opkg install $MISSING_PKGS || true
    fi
else
    echo -e "${GREEN}[+] All core dependencies are already installed.${NC}"
fi

# 3. Create Directories
echo -e "${BLUE}[+] Setting up directories...${NC}"
mkdir -p /usr/bin
mkdir -p /usr/share/pwsentinel
mkdir -p /etc/config
mkdir -p /etc/init.d
mkdir -p /var/run/pwsentinel
mkdir -p /usr/share/rpcd/acl.d
mkdir -p /usr/share/luci/menu.d
mkdir -p /www/luci-static/resources/view/pwsentinel

# 4. If installing from local files
if [ -d "./files" ]; then
    echo -e "${BLUE}[+] Installing from local repository files...${NC}"
    cp -r ./files/usr/bin/* /usr/bin/
    cp -r ./files/usr/share/pwsentinel/* /usr/share/pwsentinel/
    [ ! -f /etc/config/pwsentinel ] && cp ./files/etc/config/pwsentinel /etc/config/
    cp ./files/etc/init.d/pwsentinel /etc/init.d/
    [ -d ./files/usr/share/rpcd/acl.d ] && cp -r ./files/usr/share/rpcd/acl.d/* /usr/share/rpcd/acl.d/
    [ -d ./files/usr/share/luci/menu.d ] && cp -r ./files/usr/share/luci/menu.d/* /usr/share/luci/menu.d/
    [ -d ./files/www/luci-static/resources/view/pwsentinel ] && cp -r ./files/www/luci-static/resources/view/pwsentinel/* /www/luci-static/resources/view/pwsentinel/
fi

# 5. Fix permissions
chmod +x /usr/bin/pwsentinel
chmod +x /usr/share/pwsentinel/failsafe.sh
chmod +x /etc/init.d/pwsentinel

# 6. Enable Service & Refresh LuCI Cache
echo -e "${BLUE}[+] Enabling passwall-sentinel service...${NC}"
/etc/init.d/pwsentinel enable
/etc/init.d/pwsentinel restart

echo -e "${BLUE}[+] Refreshing LuCI Web Interface cache...${NC}"
/etc/init.d/rpcd reload >/dev/null 2>&1 || true
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/ >/dev/null 2>&1 || true

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}       passwall-sentinel installed successfully!     ${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "Web Interface: LuCI -> Services -> PassWall Sentinel"
echo -e "CLI Commands:"
echo -e "  ${YELLOW}pwsentinel check${NC}       - Run full isolated benchmark"
echo -e "  ${YELLOW}pwsentinel status${NC}      - View current status & recommendations"
echo -e "  ${YELLOW}pwsentinel apply${NC}       - Safely apply recommendations"
echo -e "  ${YELLOW}pwsentinel test-dns${NC}    - Test 50 direct DNS providers"
echo -e "  ${YELLOW}pwsentinel test-nodes${NC}  - Test PassWall 2 nodes"
echo -e "  ${YELLOW}pwsentinel rollback${NC}    - Roll back to previous snapshot"
