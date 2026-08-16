#!/bin/bash

NODE_DIR="/home/container/node"
BUN_DIR="/usr/local/bun"
GO_DIR="/usr/local/go"
export PLAYWRIGHT_BROWSERS_PATH="/usr/local/share/playwright"

mkdir -p "$NODE_DIR"
export PATH="$NODE_DIR/bin:$BUN_DIR/bin:$GO_DIR/bin:$PATH"

echo "export PATH=\"$NODE_DIR/bin:$BUN_DIR/bin:$GO_DIR/bin:\$PATH\"" > /home/container/.bashrc
echo "export NODE_PATH=\"$NODE_DIR/lib/node_modules\"" >> /home/container/.bashrc
echo "export PLAYWRIGHT_BROWSERS_PATH=\"$PLAYWRIGHT_BROWSERS_PATH\"" >> /home/container/.bashrc

if [ ! -z "${NODE_VERSION}" ]; then
    [ -x "$NODE_DIR/bin/node" ] && CURRENT_VER=$("$NODE_DIR/bin/node" -v) || CURRENT_VER="none"
    TARGET_VER=$(curl -s https://nodejs.org/dist/index.json | jq -r 'map(select(.version)) | .[] | select(.version | startswith("v'${NODE_VERSION}'")) | .version' 2>/dev/null | head -n 1)
    
    if [ -z "$TARGET_VER" ] || [ "$TARGET_VER" == "null" ]; then
         if [[ "${NODE_VERSION}" == v* ]]; then TARGET_VER="${NODE_VERSION}"; else TARGET_VER="v${NODE_VERSION}.0.0"; fi
    fi

    if [[ "$CURRENT_VER" != "$TARGET_VER" ]]; then
        rm -rf $NODE_DIR/* && cd /tmp
        curl -fL "https://nodejs.org/dist/${TARGET_VER}/node-${TARGET_VER}-linux-x64.tar.gz" -o node.tar.gz
        tar -xf node.tar.gz --strip-components=1 -C "$NODE_DIR" && rm node.tar.gz
        "$NODE_DIR/bin/npm" install -g npm@latest pm2 pnpm yarn playwright --loglevel=error
        cd /home/container
    fi
fi

if [[ "${ENABLE_CF_TUNNEL}" == "true" ]] || [[ "${ENABLE_CF_TUNNEL}" == "1" ]]; then
    if [ ! -z "${CF_TOKEN}" ]; then
        pkill -f cloudflared 2>/dev/null
        nohup cloudflared tunnel run --token ${CF_TOKEN} > /home/container/.cloudflared.log 2>&1 &
    fi
fi

# --- PHP-FPM + Nginx (via Supervisor) ---
# Aktifkan dengan env ENABLE_PHP_WEB=true (atau 1)
# WEB_ROOT bisa diarahkan ke folder public app kamu, default /home/container/public
PHP_WEB_PORT="${SERVER_PORT:-80}"
WEB_ROOT="${WEB_ROOT:-/home/container/public}"

if [[ "${ENABLE_PHP_WEB}" == "true" ]] || [[ "${ENABLE_PHP_WEB}" == "1" ]]; then
    mkdir -p "$WEB_ROOT" /home/container/logs /home/container/run

    sed -e "s#__SERVER_PORT__#${PHP_WEB_PORT}#g" \
        -e "s#__WEB_ROOT__#${WEB_ROOT}#g" \
        /etc/nginx/sites-available/php.conf.template > /etc/nginx/sites-enabled/php.conf

    pkill -f supervisord 2>/dev/null
    nohup supervisord -c /etc/supervisor/supervisord.conf > /home/container/logs/supervisord-boot.log 2>&1 &

    sleep 1
    echo -e "\033[1;32m[PHP-WEB]\033[0m Nginx + PHP-FPM aktif di port ${PHP_WEB_PORT}, root: ${WEB_ROOT}"
fi

# --- Warna ANSI ---
RESET='\033[0m'
BOLD='\033[1m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
PINK='\033[38;5;212m'
GRAY='\033[0;90m'

LINE="${GRAY}$(printf '%.0s─' $(seq 1 60))${RESET}"

# --- Helper: progress bar ---
make_bar() {
    local percent=$1
    local width=25
    local filled=$(( percent * width / 100 ))
    [ "$filled" -gt "$width" ] && filled=$width
    local empty=$(( width - filled ))
    local bar=""
    [ "$filled" -gt 0 ] && bar+=$(printf '%0.s█' $(seq 1 $filled))
    [ "$empty" -gt 0 ] && bar+=$(printf '%0.s░' $(seq 1 $empty))
    echo -n "$bar"
}

# --- Ambil data sistem ---
MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
MEM_PERCENT=$(( MEM_USED * 100 / MEM_TOTAL ))

DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_PERCENT=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

# --- IP Address (dengan opsi tampil/sembunyi) ---
PUBLIC_IP=$(curl -s ipinfo.io/ip 2>/dev/null || echo "Unknown")
if [[ "${SHOW_IP}" == "true" ]] || [[ "${SHOW_IP}" == "1" ]]; then
    IP_DISPLAY="$PUBLIC_IP"
else
    IP_DISPLAY=$(echo -n "$PUBLIC_IP" | sed 's/./•/g')
fi

clear
echo -e "${GREEN}${BOLD}"
figlet -f standard SAIRI 2>/dev/null || echo "SAIRI"
echo -e "${RESET}"
echo -e "$LINE"
echo -e "${CYAN}Location${RESET}   : $(curl -s ipinfo.io/country 2>/dev/null || echo 'Unknown')"
echo -e "${CYAN}IP Address${RESET} : ${IP_DISPLAY}"
echo -e "${CYAN}OS${RESET}         : $(grep -oP '(?<=^PRETTY_NAME=).+' /etc/os-release | tr -d '\"')"
echo -e "${CYAN}CPU${RESET}        : $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //') ($(( $(grep -c ^processor /proc/cpuinfo) )) Cores)"
echo -e "${CYAN}Uptime${RESET}     : $(uptime -p | sed 's/up //')"
echo -e "${CYAN}RAM${RESET}  ${YELLOW}${MEM_PERCENT}%${RESET}  ${GREEN}$(make_bar $MEM_PERCENT)${RESET}  ${GRAY}${MEM_USED}/${MEM_TOTAL}MB${RESET}"
echo -e "${CYAN}Disk${RESET} ${YELLOW}${DISK_PERCENT}%${RESET}  ${YELLOW}$(make_bar $DISK_PERCENT)${RESET}  ${GRAY}${DISK_USED}/${DISK_TOTAL}${RESET}"
echo -e "$LINE"
echo -e "${BLUE}Node.js${RESET}      : $(node -v 2>/dev/null || echo -e "${GRAY}Not Installed${RESET}")"
echo -e "${BLUE}Bun${RESET}          : v$(bun -v 2>/dev/null || echo -e "${GRAY}Not Installed${RESET}")"
echo -e "${BLUE}Golang${RESET}       : v$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || echo -e "${GRAY}Not Installed${RESET}")"
echo -e "${BLUE}Python${RESET}       : v$(python3 --version 2>/dev/null | awk '{print $2}' || echo -e "${GRAY}Not Installed${RESET}")"
echo -e "${BLUE}Playwright${RESET}   : $(playwright --version 2>/dev/null | head -n 1 || echo -e "${GRAY}Not Installed${RESET}")"
echo -e "${BLUE}PHP${RESET}          : $(php -v 2>/dev/null | head -n1 | awk '{print $2}' || echo -e "${GRAY}Not Installed${RESET}")"
echo -e "${BLUE}Java${RESET}         : $(java -version 2>&1 | head -n1 | awk -F'"' '{print $2}' || echo -e "${GRAY}Not Installed${RESET}")"
echo -e "$LINE"
echo -e "${MAGENTA}MySQL Client${RESET} : $(mysql --version 2>/dev/null | awk '{print $5}' | tr -d ',' || echo -e "${GRAY}Not Installed${RESET}")"
echo -e "$LINE"
if pgrep -f supervisord >/dev/null 2>&1; then
    echo -e "${GREEN}PHP-Web (Nginx+FPM)${RESET} : ${GREEN}Aktif${RESET} — port ${PHP_WEB_PORT}, root ${WEB_ROOT}"
else
    echo -e "${GRAY}PHP-Web (Nginx+FPM)${RESET} : Nonaktif (set ENABLE_PHP_WEB=true untuk aktifkan)"
fi
echo -e "$LINE"
echo -e "${PINK}${BOLD}Silahkan masukan perintah.${RESET}"

exec /bin/bash
