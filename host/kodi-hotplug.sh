#!/bin/bash
# Starts LXC when a display is connected, stops when none are connected
# Won't restart if container was stopped manually
#
# Debounce: the display must be continuously connected for more than
# CONNECT_DEBOUNCE seconds before CT 104 is started, and continuously
# disconnected for more than DISCONNECT_DEBOUNCE seconds before it counts
# as a real disconnect. A brief flicker (monitor standby, input switch,
# modeset by another container) therefore neither starts CT 104 nor
# clears the manual-stop flag.
KODI_LXC="${KODI_LXC:-104}"   # override via Environment=KODI_LXC=<id> in the unit
FLAG_FILE="/tmp/kodi-hotplug-auto-started"
MANUAL_STOP_FLAG="/tmp/kodi-hotplug-manual-stop"
STATE_FILE="/tmp/kodi-hotplug-prev-state"
CHECK_INTERVAL=1        # seconds
CONNECT_DEBOUNCE=3      # connected longer than this before starting
DISCONNECT_DEBOUNCE=3   # disconnected longer than this before acting

CONNECTED_SINCE=""
DISCONNECTED_SINCE=""

# Turn the host console back on after a container's Xorg released the
# display (Xorg leaves the CRTC disabled; chvt alone does not relight it).
reclaim_console() {
    sleep 1
    chvt 1 2>/dev/null || true
    echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null || true
}

while true; do
    NOW=$(date +%s)

    # Raw connector state
    RAW_CONNECTED=0
    for STATUS_FILE in /sys/class/drm/*/status; do
        if [ -f "$STATUS_FILE" ] && [ "$(cat "$STATUS_FILE")" = "connected" ]; then
            RAW_CONNECTED=$((RAW_CONNECTED + 1))
        fi
    done

    # Debounced state: "connected", "disconnected" or "settling"
    if [ "$RAW_CONNECTED" -gt 0 ]; then
        DISCONNECTED_SINCE=""
        [ -z "$CONNECTED_SINCE" ] && CONNECTED_SINCE=$NOW
        if [ $((NOW - CONNECTED_SINCE)) -gt "$CONNECT_DEBOUNCE" ]; then
            DISPLAY_STATE="connected"
        else
            DISPLAY_STATE="settling"
        fi
    else
        CONNECTED_SINCE=""
        [ -z "$DISCONNECTED_SINCE" ] && DISCONNECTED_SINCE=$NOW
        if [ $((NOW - DISCONNECTED_SINCE)) -gt "$DISCONNECT_DEBOUNCE" ]; then
            DISPLAY_STATE="disconnected"
        else
            DISPLAY_STATE="settling"
        fi
    fi

    # Check if LXC is running
    IS_RUNNING=$(lxc-info -n "$KODI_LXC" -s 2>/dev/null | grep -q "RUNNING" && echo "true" || echo "false")

    # Read previous state if exists
    PREV_RUNNING=""
    if [ -f "$STATE_FILE" ]; then
        PREV_RUNNING=$(cat "$STATE_FILE")
    fi

    # Detect manual stop: was running, now stopped, display not (debounced) disconnected
    if [ "$PREV_RUNNING" = "true" ] && [ "$IS_RUNNING" = "false" ] && [ "$DISPLAY_STATE" != "disconnected" ]; then
        echo "$(date) - Manual stop detected"
        touch "$MANUAL_STOP_FLAG"
        rm -f "$FLAG_FILE"
        reclaim_console
    fi

    case "$DISPLAY_STATE" in
    connected)
        if [ "$IS_RUNNING" = "false" ]; then
            if [ ! -f "$MANUAL_STOP_FLAG" ]; then
                echo "$(date) - Display connected >${CONNECT_DEBOUNCE}s, starting Kodi LXC..."
                /usr/sbin/pct start $KODI_LXC
                touch "$FLAG_FILE"
                IS_RUNNING="true"
            fi
        else
            # Running but we didn't start it - adopt it
            [ ! -f "$FLAG_FILE" ] && touch "$FLAG_FILE"
            # Clear manual stop flag since it's running
            rm -f "$MANUAL_STOP_FLAG"
        fi
        ;;
    disconnected)
        # If container is running and we're managing it, stop it
        if [ "$IS_RUNNING" = "true" ] && [ -f "$FLAG_FILE" ]; then
            echo "$(date) - No display for >${DISCONNECT_DEBOUNCE}s, stopping Kodi LXC..."
            /usr/sbin/pct stop $KODI_LXC
            IS_RUNNING="false"
            reclaim_console
        fi
        # Clean up all flags when no display
        rm -f "$FLAG_FILE" "$MANUAL_STOP_FLAG"
        ;;
    settling)
        # Brief flicker or just (re)connected: take no action
        :
        ;;
    esac

    # Save current state for next iteration
    echo "$IS_RUNNING" > "$STATE_FILE"

    sleep $CHECK_INTERVAL
done
