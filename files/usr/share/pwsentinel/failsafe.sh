#!/bin/sh
# passwall-sentinel Emergency Watchdog (Failsafe)
# Protects against router lockouts and connection blackouts

STATE_DIR="/var/run/pwsentinel"
FAIL_COUNT_FILE="${STATE_DIR}/failsafe_count"
TRIGGER_FILE="${STATE_DIR}/failsafe_triggered"
mkdir -p "${STATE_DIR}"

ENABLED=$(uci -q get pwsentinel.main.failsafe_enabled || echo "1")
[ "$ENABLED" != "1" ] && exit 0

THRESHOLD=$(uci -q get pwsentinel.main.failsafe_loss_threshold || echo "3")
COUNT=0
[ -f "$FAIL_COUNT_FILE" ] && COUNT=$(cat "$FAIL_COUNT_FILE")

# Quick multi-target connectivity test
check_online() {
    # 1. Check local gateway / direct WAN
    ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 && return 0
    # 2. Check HTTP generate_204 through active route
    curl -s --connect-timeout 3 --max-time 5 https://www.google.com/generate_204 >/dev/null 2>&1 && return 0
    return 1
}

if check_online; then
    # Reset failure counter on success
    echo "0" > "$FAIL_COUNT_FILE"
    [ -f "$TRIGGER_FILE" ] && rm -f "$TRIGGER_FILE"
    exit 0
else
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$FAIL_COUNT_FILE"
    logger -t pwsentinel "Warning: Connectivity check failed ($COUNT/$THRESHOLD)"

    if [ "$COUNT" -ge "$THRESHOLD" ]; then
        logger -t pwsentinel "EMERGENCY: Loss threshold reached. Engaging Emergency Bypass!"
        echo "triggered at $(date)" > "$TRIGGER_FILE"
        
        # Emergency Action: Temporarily disable PassWall2 to restore direct WAN
        uci set passwall2.@global[0].enabled='0'
        uci commit passwall2
        /etc/init.d/passwall2 reload >/dev/null 2>&1
        
        # Reset counter so it doesn't loop
        echo "0" > "$FAIL_COUNT_FILE"
        logger -t pwsentinel "Emergency Bypass ACTIVATED: Direct WAN connectivity restored."
    fi
fi
