#!/usr/bin/env bash

YW=`echo "\033[33m"`
RD=`echo "\033[01;31m"`
BL=`echo "\033[36m"`
GN=`echo "\033[1;92m"`
CL=`echo "\033[m"`
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
BFR="\\r\\033[K"
HOLD="-"

function msg_info() {
    local msg="$1"
    echo -ne " ${HOLD} ${YW}${msg}..."
}
function msg_ok() {
    local msg="$1"
    echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}
function msg_error() {
    local msg="$1"
    echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

# ─────────────────────────────────────────────
# Resolve install flags from INSTALL_APPS env var
# ─────────────────────────────────────────────
INSTALL_KODI_PPA="n"
INSTALL_KODI_FLATPAK="n"
INSTALL_RETROARCH="n"
INSTALL_STEAM="n"
INSTALL_FIREFOX="n"
INSTALL_BRAVE="n"
INSTALL_CHROME="n"
INSTALL_LIBREOFFICE="n"
INSTALL_VLC="n"
INSTALL_GIMP="n"

if [ -n "${INSTALL_APPS:-}" ]; then
    [[ "$INSTALL_APPS" == *"KODI_PPA"* ]]     && INSTALL_KODI_PPA="y"
    [[ "$INSTALL_APPS" == *"KODI_FLATPAK"* ]] && INSTALL_KODI_FLATPAK="y"
    [[ "$INSTALL_APPS" == *"RETROARCH"* ]]    && INSTALL_RETROARCH="y"
    [[ "$INSTALL_APPS" == *"STEAM"* ]]        && INSTALL_STEAM="y"
    [[ "$INSTALL_APPS" == *"FIREFOX"* ]]      && INSTALL_FIREFOX="y"
    [[ "$INSTALL_APPS" == *"BRAVE"* ]]        && INSTALL_BRAVE="y"
    [[ "$INSTALL_APPS" == *"CHROME"* ]]       && INSTALL_CHROME="y"
    [[ "$INSTALL_APPS" == *"LIBREOFFICE"* ]]  && INSTALL_LIBREOFFICE="y"
    [[ "$INSTALL_APPS" == *"VLC"* ]]          && INSTALL_VLC="y"
    [[ "$INSTALL_APPS" == *"GIMP"* ]]         && INSTALL_GIMP="y"
else
    # Fallback: interactive prompts if called standalone
    echo -e "\n${GN}=== Optional Software ===${CL}"
    read -p "Install Kodi? (1=apt / 2=Flatpak / n=No): " -n 1 -r KODI_CHOICE; echo
    [[ "$KODI_CHOICE" = "1" ]] && INSTALL_KODI_PPA="y"
    [[ "$KODI_CHOICE" = "2" ]] && INSTALL_KODI_FLATPAK="y"
    read -p "Install RetroArch? (y/n): "   -n 1 -r INSTALL_RETROARCH;   echo
    read -p "Install Steam? (y/n): "       -n 1 -r INSTALL_STEAM;       echo
    read -p "Install Firefox? (y/n): "     -n 1 -r INSTALL_FIREFOX;     echo
    read -p "Install Brave? (y/n): "       -n 1 -r INSTALL_BRAVE;       echo
    read -p "Install Chrome? (y/n): "      -n 1 -r INSTALL_CHROME;      echo
    read -p "Install LibreOffice? (y/n): " -n 1 -r INSTALL_LIBREOFFICE; echo
    read -p "Install VLC? (y/n): "         -n 1 -r INSTALL_VLC;         echo
    read -p "Install GIMP? (y/n): "        -n 1 -r INSTALL_GIMP;        echo

    echo -e "\n${GN}=== Boot Default ===${CL}"
    echo "Options: Desktop, Kodi, RetroArch, Steam Big Picture, Firefox, Brave, Chrome"
    read -p "Default session on boot [Desktop]: " DEFAULT_SESSION_INPUT
    [ -n "$DEFAULT_SESSION_INPUT" ] && DEFAULT_SESSION="$DEFAULT_SESSION_INPUT"

    # If a browser was chosen as default, ask for the startup URL
    if [[ "$DEFAULT_SESSION" =~ ^(Firefox|Brave|Chrome)$ ]]; then
        read -p "Browser startup URL [https://]: " BROWSER_URL_INPUT
        BROWSER_URL="${BROWSER_URL_INPUT:-https://}"
    fi
fi

DEFAULT_SESSION="${DEFAULT_SESSION:-Desktop}"
BROWSER_URL="${BROWSER_URL:-https://}"
CONFIGURE_AUDIO="${CONFIGURE_AUDIO:-no}"
KODI_PASS="${KODI_PASS:-kodi}"

# ─────────────────────────────────────────────
# Base system — Debian 13 (Trixie)
# ─────────────────────────────────────────────
msg_info "Updating system"
apt-get update -qq &>/dev/null
apt-get upgrade -y -qq &>/dev/null
msg_ok "System updated"

# Debian 13 apt sources: add contrib, non-free, non-free-firmware
# (Steam lives in contrib, AMD GPU firmware in non-free-firmware,
#  Kodi/retroarch i386 deps need the full component list.)
# Handles both classic sources.list and deb822 .sources format.
msg_info "Configuring apt sources (contrib non-free non-free-firmware)"
SOURCES_LIST="/etc/apt/sources.list"
SOURCES_DIR="/etc/apt/sources.list.d"
if [ -f "$SOURCES_LIST" ]; then
    sed -i 's/main$/main contrib non-free non-free-firmware/g' "$SOURCES_LIST"
    sed -i 's/main \[/main contrib non-free non-free-firmware \[/g' "$SOURCES_LIST" 2>/dev/null || true
fi
if [ -d "$SOURCES_DIR" ]; then
    for src_file in "$SOURCES_DIR"/*.sources; do
        [ -f "$src_file" ] || continue
        if grep -q "^Components:" "$src_file"; then
            sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' "$src_file"
            sed -i 's/^Components: main .*/Components: main contrib non-free non-free-firmware/' "$src_file"
        fi
    done
fi
apt-get update -qq &>/dev/null
msg_ok "Apt sources configured"

# AMD GPU firmware — critical for RDNA 3.5 / gfx1150 (Radeon 880M/890M)
msg_info "Installing AMD GPU firmware and Mesa drivers"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    firmware-amd-graphics \
    mesa-va-drivers \
    mesa-vulkan-drivers \
    libvulkan1 \
    vulkan-tools \
    &>/dev/null
msg_ok "AMD firmware and Mesa drivers installed"

msg_info "Installing XFCE and base X packages"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    xfce4 xfce4-goodies xfce4-terminal openbox \
    xserver-xorg xserver-xorg-video-amdgpu xserver-xorg-video-modesetting \
    xserver-xorg-input-evdev \
    zenity xterm whiptail x11-utils xdotool \
    pulseaudio pulseaudio-utils pavucontrol alsa-utils \
    software-properties-common curl wget \
    &>/dev/null
msg_ok "Installed XFCE and base X packages"

# ─────────────────────────────────────────────
# kodi user
# ─────────────────────────────────────────────
msg_info "Creating kodi user"
if ! id -u kodi &>/dev/null; then
    useradd -m -s /bin/bash -G sudo,audio,input,video,render kodi
else
    usermod -aG sudo,audio,input,video,render kodi
fi
echo "kodi:${KODI_PASS}" | chpasswd
msg_ok "kodi user ready (password set)"

# ─────────────────────────────────────────────
# lightdm — autologin to bare kodi-session (NOT xfce)
# XFCE only loads when the user explicitly selects Desktop
# ─────────────────────────────────────────────
msg_info "Configuring lightdm"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    lightdm lightdm-gtk-greeter &>/dev/null
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/autologin-kodi.conf <<'EOF'
[Seat:*]
autologin-user=kodi
autologin-session=kodi-session
EOF
msg_ok "lightdm configured (autologin → kodi-session)"

# ─────────────────────────────────────────────
# Minimal kodi-session xsession entry
# Points directly to session-manager.sh — no desktop loaded
# ─────────────────────────────────────────────
msg_info "Creating kodi-session xsession entry"
mkdir -p /usr/share/xsessions
cat > /usr/share/xsessions/kodi-session.desktop <<'EOF'
[Desktop Entry]
Name=Kodi Session
Comment=Minimal session — session manager only, no desktop
Exec=/usr/local/bin/session-manager.sh
Type=Application
EOF
msg_ok "kodi-session xsession entry created"

# ─────────────────────────────────────────────
# Xorg input detection — uses printf (no nested heredoc)
# ─────────────────────────────────────────────
msg_info "Configuring Xorg input detection"
cat > /usr/local/bin/preX-populate-input.sh <<'EOF'
#!/usr/bin/env bash
CFG=/etc/X11/xorg.conf.d/10-lxc-input.conf
mkdir -p /etc/X11/xorg.conf.d
printf 'Section "ServerFlags"\n    Option "AutoAddDevices" "True"\nEndSection\n' > "$CFG"
cd /dev/input
for input in event*; do
    printf 'Section "InputDevice"\n    Identifier "%s"\n    Option "Device" "/dev/input/%s"\n    Option "AutoServerLayout" "true"\n    Driver "evdev"\nEndSection\n' \
        "$input" "$input" >> "$CFG"
done
EOF
chmod +x /usr/local/bin/preX-populate-input.sh
mkdir -p /etc/systemd/system/lightdm.service.d
cat > /etc/systemd/system/lightdm.service.d/override.conf <<'EOF'
[Service]
ExecStartPre=/bin/sh -c '/usr/local/bin/preX-populate-input.sh'
SupplementaryGroups=video render input audio tty
EOF
systemctl daemon-reload
msg_ok "Xorg input detection configured"

# ─────────────────────────────────────────────
# PolicyKit
# ─────────────────────────────────────────────
msg_info "Configuring PolicyKit"
mkdir -p /etc/polkit-1/localauthority/50-local.d
cat > /etc/polkit-1/localauthority/50-local.d/allow-kodi.pkla <<'EOF'
[Allow kodi user all permissions]
Identity=unix-user:kodi
Action=*
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF
msg_ok "PolicyKit configured"

# ─────────────────────────────────────────────
# PulseAudio baseline
# ─────────────────────────────────────────────
msg_info "Configuring PulseAudio"
mkdir -p /home/kodi/.config/pulse
cat > /home/kodi/.config/pulse/default.pa <<'EOF'
#!/usr/bin/pulseaudio -nF
.include /etc/pulse/default.pa
unload-module module-suspend-on-idle
EOF
chown -R kodi:kodi /home/kodi/.config/pulse
msg_ok "PulseAudio base config set"

# ─────────────────────────────────────────────
# Audio device configuration (optional at install time)
# ─────────────────────────────────────────────
SKIP_AUDIO=true
SELECTED_CARD=""
SELECTED_DEV=""
SELECTED_DEVICE_NAME=""

if [[ "${CONFIGURE_AUDIO}" =~ ^[Yy] ]]; then
    mapfile -t DEVICES      < <(aplay -l 2>/dev/null | grep -E "^card [0-9]+" | sed 's/card \([0-9]\+\):.*device \([0-9]\+\):.*/\1,\2/')
    mapfile -t DEVICE_NAMES < <(aplay -l 2>/dev/null | grep -E "^card [0-9]+" | sed 's/card [0-9]\+: \(.*\), device [0-9]\+: \(.*\)/\1 - \2/')

    if [ ${#DEVICES[@]} -eq 0 ]; then
        msg_error "No audio devices detected — configure later from session menu"
    else
        SKIP_AUDIO=false
        if [ ${#DEVICES[@]} -eq 1 ]; then
            SELECTED_INDEX=0
        else
            for i in "${!DEVICES[@]}"; do
                IFS=',' read -r C D <<< "${DEVICES[$i]}"
                echo -e "  ${GN}$((i+1)).${CL} hw:${C},${D} — ${DEVICE_NAMES[$i]}"
            done
            while true; do
                read -p "Select device [1-${#DEVICES[@]}]: " CHOICE
                if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le ${#DEVICES[@]} ]; then
                    SELECTED_INDEX=$((CHOICE - 1)); break
                fi
            done
        fi
        IFS=',' read -r SELECTED_CARD SELECTED_DEV <<< "${DEVICES[$SELECTED_INDEX]}"
        SELECTED_DEVICE_NAME="${DEVICE_NAMES[$SELECTED_INDEX]}"

        cat > /home/kodi/.config/pulse/default.pa <<EOF
#!/usr/bin/pulseaudio -nF
.include /etc/pulse/default.pa
load-module module-alsa-sink device=hw:${SELECTED_CARD},${SELECTED_DEV} sink_name=selected_output
set-default-sink selected_output
unload-module module-suspend-on-idle
EOF
        cat > /etc/asound.conf <<EOF
defaults.pcm.card ${SELECTED_CARD}
defaults.pcm.device ${SELECTED_DEV}
defaults.ctl.card ${SELECTED_CARD}
EOF
        chown kodi:kodi /home/kodi/.config/pulse/default.pa
        msg_ok "Audio configured: hw:${SELECTED_CARD},${SELECTED_DEV} — ${SELECTED_DEVICE_NAME}"
    fi
fi

# ─────────────────────────────────────────────
# Configure Audio helper script
# ─────────────────────────────────────────────
msg_info "Installing Configure Audio tool"
cat > /usr/local/bin/configure-audio.sh <<'AUDIOEOF'
#!/usr/bin/env bash
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

SCREEN_W=$(xdpyinfo 2>/dev/null | grep -m1 dimensions | awk '{print $2}' | cut -dx -f1)
SCREEN_W=${SCREEN_W:-800}

zenity --info --title="Audio Configuration" \
    --text="This will help you configure your audio output device.\n\nClick OK to continue." \
    --width=400 2>/dev/null

mapfile -t DEVICES      < <(aplay -l 2>/dev/null | grep -E "^card [0-9]+" | sed 's/card \([0-9]\+\):.*device \([0-9]\+\):.*/\1,\2/')
mapfile -t DEVICE_NAMES < <(aplay -l 2>/dev/null | grep -E "^card [0-9]+" | sed 's/card [0-9]\+: \(.*\), device [0-9]\+: \(.*\)/\1 - \2/')

if [ ${#DEVICES[@]} -eq 0 ]; then
    zenity --error --title="No Devices Found" \
        --text="No audio devices detected.\n\nMake sure /dev/snd is passed through to the container." \
        --width=360 2>/dev/null
    exit 1
fi

LIST_ARGS=()
for i in "${!DEVICES[@]}"; do
    IFS=',' read -r C D <<< "${DEVICES[$i]}"
    LIST_ARGS+=("FALSE" "hw:${C},${D}" "${DEVICE_NAMES[$i]}")
done

SELECTED=$(zenity --list --radiolist \
    --title="Select Audio Device" \
    --text="Choose your audio output device:" \
    --column="Select" --column="Device" --column="Description" \
    "${LIST_ARGS[@]}" \
    --width="$SCREEN_W" \
    --height=$(( 160 + ${#DEVICES[@]} * 60 )) 2>/dev/null)
[ -z "$SELECTED" ] && exit 0

SEL_CARD=$(echo "$SELECTED" | sed 's/hw:\([0-9]\+\),.*/\1/')
SEL_DEV=$(echo  "$SELECTED" | sed 's/hw:[0-9]\+,\([0-9]\+\)/\1/')

zenity --info --title="Test Audio" \
    --text="Playing test tone on $SELECTED\n\nClick OK to play." \
    --width=380 2>/dev/null
aplay -D plughw:${SEL_CARD},${SEL_DEV} /usr/share/sounds/alsa/Front_Center.wav 2>/dev/null

if zenity --question --title="Audio OK?" \
    --text="Did you hear the test sound on $SELECTED?" --width=340 2>/dev/null; then
    mkdir -p ~/.config/pulse
    cat > ~/.config/pulse/default.pa <<EOF
#!/usr/bin/pulseaudio -nF
.include /etc/pulse/default.pa
load-module module-alsa-sink device=hw:${SEL_CARD},${SEL_DEV} sink_name=selected_output
set-default-sink selected_output
unload-module module-suspend-on-idle
EOF
    sudo bash -c "cat > /etc/asound.conf <<EOF
defaults.pcm.card ${SEL_CARD}
defaults.pcm.device ${SEL_DEV}
defaults.ctl.card ${SEL_CARD}
EOF"
    pulseaudio -k 2>/dev/null; sleep 1
    zenity --info --title="Done" \
        --text="Audio set to: $SELECTED\n\nRestart open apps to apply." \
        --width=360 2>/dev/null
else
    zenity --question --title="Try Again?" \
        --text="Test failed. Try a different device?" --width=300 2>/dev/null \
        && exec "$0"
fi
AUDIOEOF
chmod +x /usr/local/bin/configure-audio.sh
msg_ok "Configure Audio tool installed"

# ─────────────────────────────────────────────
# RETROARCH — installed from libretro's official buildbot
# The PPA build has the online core downloader compiled out.
# The buildbot binary is the full build with online updater intact.
# AppImage is extracted (no FUSE needed) to /opt/retroarch-bin.
# ─────────────────────────────────────────────
RETROARCH_INSTALLED=false
if [[ "${INSTALL_RETROARCH}" =~ ^[Yy] ]]; then
    msg_info "Installing RetroArch dependencies"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        libgl1 libgles2 libegl1 \
        libsdl2-2.0-0 libavcodec61 libavformat61 libswscale8 \
        libfreetype6 libasound2t64 curl p7zip-full fuse unzip &>/dev/null
    msg_ok "RetroArch dependencies installed"

    msg_info "Fetching latest RetroArch nightly build"
    # Linux builds are dated .7z archives in the x86_64 directory.
    # The /latest/ subfolder only has individual core .so.zip files — no AppImage.
    BUILDBOT_DIR="https://buildbot.libretro.com/nightly/linux/x86_64"
    ARCHIVE=$(curl -s "${BUILDBOT_DIR}/" \
        | grep -oP '\d{4}-\d{2}-\d{2}_RetroArch\.7z' \
        | grep -v Qt | sort | tail -1)

    if [ -z "$ARCHIVE" ]; then
        msg_error "Could not determine archive filename — falling back to Flatpak"
    else
        wget -q "${BUILDBOT_DIR}/${ARCHIVE}" -O /tmp/retroarch.7z 2>/dev/null
        if [ -s /tmp/retroarch.7z ]; then
            msg_ok "Downloaded: $ARCHIVE"
            msg_info "Extracting RetroArch"
            mkdir -p /tmp/retroarch-extract
            7z x /tmp/retroarch.7z -o/tmp/retroarch-extract &>/dev/null
            APPIMAGE=$(find /tmp/retroarch-extract -name '*.AppImage' | head -1)
            if [ -n "$APPIMAGE" ]; then
                mv "$APPIMAGE" /opt/RetroArch.AppImage
                chmod +x /opt/RetroArch.AppImage
                cat > /usr/local/bin/retroarch <<'EOF'
#!/usr/bin/env bash
exec /opt/RetroArch.AppImage "$@"
EOF
                chmod +x /usr/local/bin/retroarch
                RETROARCH_INSTALLED=true
                msg_ok "RetroArch installed from buildbot (online updater enabled)"
            else
                msg_error "AppImage not found in archive — falling back to Flatpak"
            fi
            rm -rf /tmp/retroarch.7z /tmp/retroarch-extract
        else
            msg_error "Download failed — falling back to Flatpak"
            rm -f /tmp/retroarch.7z
        fi
    fi

    # apt fallback if buildbot download fails (retroarch is in the Debian 13 repos)
    if [ "$RETROARCH_INSTALLED" = false ]; then
        msg_error "Buildbot failed — falling back to apt repos"
        if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq retroarch retroarch-assets 2>/dev/null \
                && command -v retroarch &>/dev/null; then
            RETROARCH_INSTALLED=true
            msg_ok "RetroArch installed via apt (fallback — online updater enabled)"
        else
            msg_error "RetroArch installation failed"
        fi
    fi

    # Minimal retroarch.cfg — online updater manages all paths itself
    if [ "$RETROARCH_INSTALLED" = true ]; then
        msg_info "Configuring RetroArch defaults"
        RETROARCH_CFG_DIR="/home/kodi/.config/retroarch"
        mkdir -p "$RETROARCH_CFG_DIR"
        cat > "$RETROARCH_CFG_DIR/retroarch.cfg" <<'EOF'
# RetroArch defaults — cores pre-installed by setup script
video_fullscreen = "true"
video_windowed_fullscreen = "false"
video_threaded = "true"
audio_sync = "true"
libretro_directory = "~/.config/retroarch/cores"
input_exit_emulator = escape
input_menu_toggle = f1
EOF
        chown -R kodi:kodi "$RETROARCH_CFG_DIR"
        msg_ok "RetroArch configured (use Online Updater → Core Downloader for cores)"

        # ── Download 10 popular cores from buildbot ───────────────────────────
        msg_info "Downloading popular RetroArch cores"
        CORES_URL="https://buildbot.libretro.com/nightly/linux/x86_64/latest"
        CORES_DIR="/home/kodi/.config/retroarch/cores"
        mkdir -p "$CORES_DIR"

        POPULAR_CORES=(
            "snes9x_libretro.so.zip"          # SNES
            "mgba_libretro.so.zip"             # GBA / GB / GBC
            "mupen64plus_next_libretro.so.zip" # N64
            "genesis_plus_gx_libretro.so.zip"  # Mega Drive / Genesis
            "mednafen_psx_hw_libretro.so.zip"  # PS1
            "fbneo_libretro.so.zip"            # Arcade (FinalBurn Neo)
            "mesen_libretro.so.zip"            # NES
            "melonds_libretro.so.zip"          # Nintendo DS
            "ppsspp_libretro.so.zip"           # PSP
            "dolphin_libretro.so.zip"          # GameCube / Wii
        )

        INSTALLED=0; FAILED=0
        for zip in "${POPULAR_CORES[@]}"; do
            if wget -q "${CORES_URL}/${zip}" -O "/tmp/${zip}" 2>/dev/null; then
                unzip -q -o "/tmp/${zip}" -d "$CORES_DIR" 2>/dev/null && \
                    INSTALLED=$(( INSTALLED + 1 )) || FAILED=$(( FAILED + 1 ))
                rm -f "/tmp/${zip}"
            else
                FAILED=$(( FAILED + 1 ))
                msg_error "Failed: $zip"
            fi
        done
        chown -R kodi:kodi "$CORES_DIR"
        msg_ok "Installed $INSTALLED popular cores (use Online Updater for more)"
        [ "$FAILED" -gt 0 ] && msg_error "$FAILED cores failed to download"
    fi
fi

# ─────────────────────────────────────────────
# KODI — apt (Debian 13 repo, v21.x) or Flatpak
# Note: the team-xbmc PPA has no Debian 13 build, so KODI_PPA maps
#       to the trixie repo version (same major line).
# ─────────────────────────────────────────────
KODI_INSTALLED=false
if [[ "${INSTALL_KODI_PPA}" =~ ^[Yy] ]]; then
    msg_info "Installing Kodi from Debian 13 repos (v21.x)"
    dpkg --add-architecture i386 &>/dev/null
    apt-get update -qq &>/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq kodi &>/dev/null
    apt-get install -y -f -qq &>/dev/null
    command -v kodi &>/dev/null \
        && KODI_INSTALLED=true && msg_ok "Kodi installed via apt" \
        || msg_error "Kodi apt install failed"
elif [[ "${INSTALL_KODI_FLATPAK}" =~ ^[Yy] ]]; then
    msg_info "Installing Kodi via Flatpak (v21.x)"
    apt-get install -y -qq flatpak &>/dev/null
    flatpak remote-add --if-not-exists flathub \
        https://flathub.org/repo/flathub.flatpakrepo &>/dev/null
    flatpak install -y --noninteractive flathub tv.kodi.Kodi &>/dev/null
    flatpak list 2>/dev/null | grep -q "tv.kodi.Kodi" \
        && KODI_INSTALLED=true && msg_ok "Kodi Flatpak installed" \
        || msg_error "Kodi Flatpak install failed"
fi

# ─────────────────────────────────────────────
# STEAM
# ─────────────────────────────────────────────
STEAM_INSTALLED=false
if [[ "${INSTALL_STEAM}" =~ ^[Yy] ]]; then
    msg_info "Installing Steam"
    dpkg --add-architecture i386 &>/dev/null
    apt-get update -qq &>/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq steam-installer &>/dev/null
    apt-get install -y -f -qq &>/dev/null
    ( command -v steam &>/dev/null || [ -f /usr/games/steam ] ) \
        && STEAM_INSTALLED=true && msg_ok "Steam installed" \
        || msg_error "Steam install failed"
fi

# ─────────────────────────────────────────────
# Optional apps
# ─────────────────────────────────────────────
if [[ "${INSTALL_FIREFOX}" =~ ^[Yy] ]]; then
    msg_info "Installing Firefox"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq firefox &>/dev/null \
        && msg_ok "Firefox installed" || msg_error "Firefox failed"
fi
if [[ "${INSTALL_BRAVE}" =~ ^[Yy] ]]; then
    msg_info "Installing Brave"
    curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
        https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg 2>/dev/null
    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] \
https://brave-browser-apt-release.s3.brave.com/ stable main" \
        > /etc/apt/sources.list.d/brave-browser-release.list
    apt-get update -qq &>/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq brave-browser &>/dev/null \
        && msg_ok "Brave installed" || msg_error "Brave failed"
fi
if [[ "${INSTALL_CHROME}" =~ ^[Yy] ]]; then
    msg_info "Installing Google Chrome"
    wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
        -O /tmp/chrome.deb 2>/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq /tmp/chrome.deb &>/dev/null
    rm -f /tmp/chrome.deb
    command -v google-chrome &>/dev/null \
        && msg_ok "Chrome installed" || msg_error "Chrome failed"
fi
if [[ "${INSTALL_LIBREOFFICE}" =~ ^[Yy] ]]; then
    msg_info "Installing LibreOffice"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libreoffice &>/dev/null \
        && msg_ok "LibreOffice installed" || msg_error "LibreOffice failed"
fi
if [[ "${INSTALL_VLC}" =~ ^[Yy] ]]; then
    msg_info "Installing VLC"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq vlc &>/dev/null \
        && msg_ok "VLC installed" || msg_error "VLC failed"
fi
if [[ "${INSTALL_GIMP}" =~ ^[Yy] ]]; then
    msg_info "Installing GIMP"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gimp &>/dev/null \
        && msg_ok "GIMP installed" || msg_error "GIMP failed"
fi

# ─────────────────────────────────────────────
# Session Manager
#
# Architecture:
#   lightdm autologins to "kodi-session" which runs this script directly.
#   No desktop is loaded. The screen is black except for the zenity dialog.
#   Apps launch fullscreen (kodi by default, retroarch --fullscreen,
#   steam -gamepadui). When an app exits the loop brings the dialog back.
#   Selecting "Desktop" runs XFCE as a child process — menu reappears on exit.
#
# Steam silent mode:
#   When a non-Steam session is launched AND Steam is installed, start Steam
#   with -silent so it updates games in the background. Steam's own lock
#   prevents double-launch if already running.
# ─────────────────────────────────────────────
msg_info "Installing Session Manager"

cat > /usr/local/bin/session-manager.sh <<'SESSIONEOF'
#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Session Manager — runs as the entire X session via kodi-session.desktop.
# Uses zenity for UI (mouse-friendly). Font size scaled to screen height.
# FIRST_RUN uses a /run flag file so countdown only fires on true system boot,
# not on every login (e.g. after returning from XFCE desktop).
# ─────────────────────────────────────────────────────────────────────────────
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

CONFIG_DIR="$HOME/.config/kodi-session"
CONFIG_FILE="$CONFIG_DIR/default"
URL_FILE="$CONFIG_DIR/browser-url"
COUNTDOWN_SECS=5
BOOT_FLAG="/run/kodi-session-booted"

mkdir -p "$CONFIG_DIR"
xsetroot -solid black 2>/dev/null || true

# ── Screen dimensions ─────────────────────────────────────────────────────────
SCREEN_W=$(xdpyinfo 2>/dev/null | grep -m1 dimensions | awk '{print $2}' | cut -dx -f1)
SCREEN_H=$(xdpyinfo 2>/dev/null | grep -m1 dimensions | awk '{print $2}' | cut -dx -f2)
SCREEN_W=${SCREEN_W:-1920}
SCREEN_H=${SCREEN_H:-1080}

# ── Scale GTK font so zenity text is readable on a TV ────────────────────────
FONT_PT=$(( SCREEN_H / 54 ))
[ "$FONT_PT" -lt 16 ] && FONT_PT=16
mkdir -p "$HOME/.config/gtk-3.0"
cat > "$HOME/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-font-name = Sans ${FONT_PT}
EOF

# ── Detect installed apps ─────────────────────────────────────────────────────
detect_apps() {
    HAVE_KODI=false; HAVE_RETROARCH=false; HAVE_STEAM=false
    HAVE_FIREFOX=false; HAVE_BRAVE=false; HAVE_CHROME=false
    ( command -v kodi &>/dev/null || \
      flatpak list 2>/dev/null | grep -q "tv.kodi.Kodi" ) && HAVE_KODI=true
    command -v retroarch &>/dev/null && HAVE_RETROARCH=true
    ( command -v steam &>/dev/null || [ -f /usr/games/steam ] ) && HAVE_STEAM=true
    command -v firefox &>/dev/null && HAVE_FIREFOX=true
    command -v brave-browser &>/dev/null && HAVE_BRAVE=true
    command -v google-chrome &>/dev/null && HAVE_CHROME=true
}

# ── Only start Steam silently if user is already logged in ───────────────────
# Prevents the login window from popping up over the session manager.
maybe_start_steam_silent() {
    $HAVE_STEAM || return 0
    pgrep -x steam &>/dev/null && return 0
    if command -v steam &>/dev/null; then
        steam -silent &>/dev/null &
    elif [ -f /usr/games/steam ]; then
        /usr/games/steam -silent &>/dev/null &
    fi
}

# ── Build zenity menu rows ────────────────────────────────────────────────────
build_menu_rows() {
    MENU_ROWS=()
    detect_apps
    $HAVE_KODI      && MENU_ROWS+=("Kodi"              "Media center (fullscreen)")
    $HAVE_RETROARCH && MENU_ROWS+=("RetroArch"         "Emulation frontend (fullscreen)")
    $HAVE_STEAM     && MENU_ROWS+=("Steam Big Picture" "Gaming — Big Picture mode")
    $HAVE_FIREFOX   && MENU_ROWS+=("Firefox"           "Web browser (kiosk mode)")
    $HAVE_BRAVE     && MENU_ROWS+=("Brave"             "Web browser (kiosk mode)")
    $HAVE_CHROME    && MENU_ROWS+=("Chrome"            "Web browser (kiosk mode)")
    MENU_ROWS+=("─────────────────────" "")
    MENU_ROWS+=("Desktop"              "Load XFCE desktop environment")
    MENU_ROWS+=("─────────────────────" "")
    MENU_ROWS+=("Configure Audio"      "Set up audio output device")
    MENU_ROWS+=("Change Default"       "Choose which app launches on boot")
    MENU_ROWS+=("Set Browser URL"      "Set the URL opened in kiosk browser mode")
    MENU_ROWS+=("─────────────────────" "")
    MENU_ROWS+=("Restart"              "Restart the system")
    MENU_ROWS+=("Shutdown"             "Shut down the system")
}

# ── 5-second countdown before auto-launching default ─────────────────────────
show_countdown() {
    local label="$1"
    (
        for i in $(seq "$COUNTDOWN_SECS" -1 1); do
            echo $(( 100 - (i * 100 / COUNTDOWN_SECS) ))
            echo "# Launching $label in $i second(s)...

Press Cancel to open the session menu."
            sleep 1
        done
        echo "100"
    ) | zenity --progress \
            --title="Session Manager" \
            --text="Preparing $label..." \
            --width="$SCREEN_W" \
            --auto-close \
            2>/dev/null
    return $?
}

# ── Session selection menu ────────────────────────────────────────────────────
show_menu() {
    build_menu_rows
    local default_label
    default_label=$(cat "$CONFIG_FILE" 2>/dev/null || echo "")
    local subtitle
    [ -n "$default_label" ] \
        && subtitle="\nBoot default: <b>$default_label</b>" \
        || subtitle="\nNo boot default set."

    zenity --list \
        --title="Session Manager" \
        --text="Welcome! What would you like to do?$subtitle" \
        --column="Session" --column="Description" \
        --width="$SCREEN_W" --height="$SCREEN_H" \
        --hide-column=0 --print-column=1 \
        "${MENU_ROWS[@]}" \
        2>/dev/null
}

# ── Change boot default ───────────────────────────────────────────────────────
change_default() {
    detect_apps
    local opts=()
    $HAVE_KODI      && opts+=("Kodi"              "Launch Kodi on boot")
    $HAVE_RETROARCH && opts+=("RetroArch"         "Launch RetroArch on boot")
    $HAVE_STEAM     && opts+=("Steam Big Picture" "Launch Steam Big Picture on boot")
    $HAVE_FIREFOX   && opts+=("Firefox"           "Launch Firefox in kiosk mode on boot")
    $HAVE_BRAVE     && opts+=("Brave"             "Launch Brave in kiosk mode on boot")
    $HAVE_CHROME    && opts+=("Chrome"            "Launch Chrome in kiosk mode on boot")
    opts+=("Desktop" "Show session menu on boot (no auto-launch)")

    local chosen
    chosen=$(zenity --list \
        --title="Change Boot Default" \
        --text="Which session launches automatically on boot?" \
        --column="Session" --column="Description" \
        --width="$SCREEN_W" --height="$SCREEN_H" \
        --hide-column=0 --print-column=1 \
        "${opts[@]}" 2>/dev/null)
    [ -z "$chosen" ] && return

    if [ "$chosen" = "Desktop" ]; then
        rm -f "$CONFIG_FILE"
        zenity --info --title="Default Cleared" \
            --text="Boot default cleared.\nSession menu will appear on next boot." \
            --width=360 2>/dev/null
    else
        echo "$chosen" > "$CONFIG_FILE"
        zenity --info --title="Default Saved" \
            --text="Boot default set to: <b>$chosen</b>\n\nTakes effect on next boot." \
            --width=360 2>/dev/null
    fi
}

set_browser_url() {
    local current
    current=$(cat "$URL_FILE" 2>/dev/null || echo "https://")
    local url
    url=$(zenity --entry \
        --title="Set Browser URL" \
        --text="Enter the URL to open in kiosk mode:\n(Leave as https:// for blank start page)" \
        --entry-text="$current" \
        --width=600 2>/dev/null)
    [ -z "$url" ] && return
    echo "$url" > "$URL_FILE"
    zenity --info --title="URL Saved" \
        --text="Browser URL set to:\n<b>$url</b>" \
        --width=400 2>/dev/null
}

launch_browser() {
    local bin="$1"
    local url
    url=$(cat "$URL_FILE" 2>/dev/null || echo "https://")
    "$bin" --kiosk "$url"
}

# ── Main loop ─────────────────────────────────────────────────────────────────
detect_apps

# Use /run flag so countdown only fires on true system boot.
# /run is a tmpfs — it clears on reboot but survives logout/login cycles.
FIRST_RUN=false
if [ ! -f "$BOOT_FLAG" ]; then
    FIRST_RUN=true
    touch "$BOOT_FLAG" 2>/dev/null || true
fi

# xfwm4 as persistent WM for the whole session.
# - Gives zenity proper input focus so keyboard/mouse always works
# - No strut/gap (unlike matchbox)
# - When XFCE is selected, startxfce4 finds xfwm4 already running — no flicker
# - Steam BPM is fullscreen so xfwm4 stays out of the way entirely
xfwm4 --compositor=on &>/dev/null &
sleep 1  # give xfwm4 a moment to register before the first zenity/steam launch

xset s off        # disable screensaver
xset s noblank    # disable screen blanking
xset -dpms        # disable DPMS (display power management)

while true; do
    DEFAULT=$(cat "$CONFIG_FILE" 2>/dev/null || echo "")

    if [ "$FIRST_RUN" = true ] && [ -n "$DEFAULT" ] && [ "$DEFAULT" != "Desktop" ]; then
        if show_countdown "$DEFAULT"; then
            CHOICE="$DEFAULT"
        else
            CHOICE=$(show_menu)
        fi
    else
        CHOICE=$(show_menu)
    fi

    FIRST_RUN=false

    case "$CHOICE" in
        "─────────────────────"|"") continue ;;
    esac

    case "$CHOICE" in
        "Kodi")
            if command -v kodi &>/dev/null; then kodi
            else flatpak run tv.kodi.Kodi; fi
            ;;
        "RetroArch")
            retroarch --fullscreen
            ;;
        "Steam Big Picture")
            STEAM_BIN="steam"
            [ -f /usr/games/steam ] && STEAM_BIN="/usr/games/steam"
            $STEAM_BIN -gamepadui -fulldesktopres

            # Repaint root — Steam BPM leaves display black on exit.
            sleep 1
            xsetroot -solid black 2>/dev/null || true
            sleep 1
            ;;
        "Desktop")
            # xfwm4 is already running — startxfce4 finds it and continues seamlessly.
            # Steam runs silently in desktop session for updates/friends.
            maybe_start_steam_silent
            startxfce4
            # Kill silent Steam when user exits desktop.
            pkill -x steam 2>/dev/null || true
            ;;
        "Firefox")
            launch_browser firefox
            ;;
        "Brave")
            launch_browser brave-browser
            ;;
        "Chrome")
            launch_browser google-chrome
            ;;
        "Set Browser URL")
            set_browser_url
            ;;
        "Configure Audio")
            /usr/local/bin/configure-audio.sh
            ;;
        "Change Default")
            change_default
            ;;
        "Restart")
            systemctl reboot
            ;;
        "Shutdown")
            systemctl poweroff
            ;;
    esac

    xsetroot -solid black 2>/dev/null || true
done
SESSIONEOF
chmod +x /usr/local/bin/session-manager.sh

# Write boot default from install-time choice
SESSION_CONFIG_DIR="/home/kodi/.config/kodi-session"
mkdir -p "$SESSION_CONFIG_DIR"
if [ "$DEFAULT_SESSION" != "Desktop" ] && [ -n "$DEFAULT_SESSION" ]; then
    echo "$DEFAULT_SESSION" > "$SESSION_CONFIG_DIR/default"
    msg_ok "Session default written: $DEFAULT_SESSION"
else
    msg_ok "Session default: show menu on boot"
fi
# Write browser URL if set
if [ -n "$BROWSER_URL" ] && [ "$BROWSER_URL" != "https://" ]; then
    echo "$BROWSER_URL" > "$SESSION_CONFIG_DIR/browser-url"
    msg_ok "Browser URL written: $BROWSER_URL"
fi
chown -R kodi:kodi "$SESSION_CONFIG_DIR"
msg_ok "Session Manager installed"

# ─────────────────────────────────────────────
# XFCE autostart — only used when user selects Desktop
# Puts a session manager launcher on the desktop for convenience
# ─────────────────────────────────────────────
msg_info "Configuring XFCE desktop shortcuts"
mkdir -p /home/kodi/.config/autostart
mkdir -p /home/kodi/Desktop

# ── Shortcuts for installed apps ─────────────────────────────────────────────
if [ "$KODI_INSTALLED" = true ]; then
    if [[ "${INSTALL_KODI_PPA}" =~ ^[Yy] ]]; then
        cat > /home/kodi/Desktop/kodi.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Kodi
Comment=Launch Kodi Media Center
Exec=kodi
Icon=kodi
Terminal=false
X-XFCE-DesktopFile-Trusted=true
EOF
    else
        cat > /home/kodi/Desktop/kodi.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Kodi
Comment=Launch Kodi Media Center (Flatpak)
Exec=flatpak run tv.kodi.Kodi
Icon=kodi
Terminal=false
X-XFCE-DesktopFile-Trusted=true
EOF
    fi
fi

if [ "$RETROARCH_INSTALLED" = true ]; then
    cat > /home/kodi/Desktop/retroarch.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=RetroArch
Comment=Launch RetroArch emulation frontend
Exec=retroarch --fullscreen
Icon=retroarch
Terminal=false
Categories=Game;Emulator;
X-XFCE-DesktopFile-Trusted=true
EOF
    # The buildbot AppImage does not ship a .desktop file so RetroArch won't
    # appear in the applications menu without this. Create it in
    # /usr/share/applications/.
    cat > /usr/share/applications/retroarch.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=RetroArch
Comment=Emulation frontend
Exec=retroarch --fullscreen
Icon=retroarch
Terminal=false
Categories=Game;Emulator;
Keywords=game;emulator;retro;
EOF
    update-desktop-database /usr/share/applications/ &>/dev/null || true
fi

if [ "$STEAM_INSTALLED" = true ]; then
    cat > /usr/local/bin/steam-bpm.sh <<'EOF'
#!/usr/bin/env bash
export DISPLAY="${DISPLAY:-:0}"
steam -gamepadui -fulldesktopres
EOF
    chmod +x /usr/local/bin/steam-bpm.sh

    cat > /home/kodi/Desktop/steam-bigpicture.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Steam Big Picture
Comment=Launch Steam in Big Picture mode
Exec=/usr/local/bin/steam-bpm.sh
Icon=steam
Terminal=false
X-XFCE-DesktopFile-Trusted=true
EOF
    cat > /home/kodi/Desktop/steam.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Steam
Comment=Launch Steam normally
Exec=steam
Icon=steam
Terminal=false
X-XFCE-DesktopFile-Trusted=true
EOF
fi

cat > /home/kodi/Desktop/session-manager.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Exit to Session Manager
Comment=End desktop session and return to session chooser
Exec=pkill -TERM -u kodi xfce4-session
Icon=system-log-out
Terminal=false
X-XFCE-DesktopFile-Trusted=true
EOF

cat > /home/kodi/Desktop/configure-audio.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Configure Audio
Comment=Set audio output device
Exec=/usr/local/bin/configure-audio.sh
Icon=multimedia-volume-control
Terminal=false
X-XFCE-DesktopFile-Trusted=true
EOF

cat > /home/kodi/Desktop/volume-control.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Volume Control (ALSA)
Exec=xfce4-terminal --title="Volume Control" -e "alsamixer"
Icon=multimedia-volume-control
Terminal=false
X-XFCE-DesktopFile-Trusted=true
EOF

# systemctl poweroff/reboot work from the desktop because the polkit rule
# grants the kodi user full permissions. xfce4-session-logout --halt/--reboot
# triggers a DBus InvalidArgs bug on some distros and must not be used.
cat > /home/kodi/Desktop/shutdown.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Shutdown
Exec=systemctl poweroff
Icon=system-shutdown
Terminal=false
X-XFCE-DesktopFile-Trusted=true
EOF

cat > /home/kodi/Desktop/reboot.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Reboot
Exec=systemctl reboot
Icon=system-reboot
Terminal=false
X-XFCE-DesktopFile-Trusted=true
EOF

for f in /home/kodi/Desktop/*.desktop; do
    chmod +x "$f"
    chown kodi:kodi "$f"
done

# gio set metadata::trusted only works inside a live GVfs session, so we
# create a self-deleting XFCE autostart script that runs it on first login.
cat > /home/kodi/.config/autostart/trust-desktop-shortcuts.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Trust Desktop Shortcuts
Comment=Sets trusted flag on desktop icons (runs once)
Exec=/usr/local/bin/trust-desktop-shortcuts.sh
X-XFCE-Autostart-enabled=true
EOF

cat > /usr/local/bin/trust-desktop-shortcuts.sh <<'EOF'
#!/usr/bin/env bash
# Runs once on first XFCE login to mark all desktop shortcuts as trusted.
# Deletes itself after running so it never appears again.
sleep 2  # give GVfs a moment to start
for f in ~/Desktop/*.desktop; do
    gio set "$f" metadata::trusted true 2>/dev/null || true
done
rm -f ~/.config/autostart/trust-desktop-shortcuts.desktop
rm -f "$0"
EOF
chmod +x /usr/local/bin/trust-desktop-shortcuts.sh

msg_ok "Desktop shortcuts created"

# ─────────────────────────────────────────────
# Per-app installer shortcuts for skipped apps
# ─────────────────────────────────────────────
msg_info "Creating app installer shortcuts"

write_installer_shortcut() {
    local key="$1"
    local label="$2"
    local cmd="$3"
    local script="/usr/local/bin/install-${key,,}.sh"
    local desktop="/home/kodi/Desktop/install-${key,,}.desktop"

    cat > "$script" <<SCRIPTEOF
#!/usr/bin/env bash
echo "${label}..."
${cmd}
echo "Done."
# Remove this installer shortcut — app is now installed.
rm -f "${desktop}" "${script}"
read -p "Press Enter to close..."
SCRIPTEOF
    chmod +x "$script"

    cat > "$desktop" <<DESKEOF
[Desktop Entry]
Version=1.0
Type=Application
Name=${label}
Exec=xfce4-terminal --hold --geometry=120x35 -e "sudo ${script}"
Terminal=false
X-XFCE-DesktopFile-Trusted=true
DESKEOF
    chmod +x "$desktop"
    chown kodi:kodi "$desktop"
}

! [ "$RETROARCH_INSTALLED" = true ] && \
write_installer_shortcut "RETROARCH" "Install RetroArch" \
'apt-get install -y -qq libgl1 libgles2 libegl1 libsdl2-2.0-0 libavcodec61 libavformat61 libswscale8 libfreetype6 libasound2t64 curl p7zip-full fuse &>/dev/null
BUILDBOT_DIR="https://buildbot.libretro.com/nightly/linux/x86_64"
ARCHIVE=$(curl -s "${BUILDBOT_DIR}/" | grep -oP "\d{4}-\d{2}-\d{2}_RetroArch\.7z" | grep -v Qt | sort | tail -1)
if [ -n "$ARCHIVE" ]; then
    echo "Downloading $ARCHIVE..."
    wget -q "${BUILDBOT_DIR}/${ARCHIVE}" -O /tmp/retroarch.7z
    mkdir -p /tmp/retroarch-extract
    7z x /tmp/retroarch.7z -o/tmp/retroarch-extract &>/dev/null
    APPIMAGE=$(find /tmp/retroarch-extract -name "*.AppImage" | head -1)
    if [ -n "$APPIMAGE" ]; then
        mv "$APPIMAGE" /opt/RetroArch.AppImage
        chmod +x /opt/RetroArch.AppImage
        printf "#!/usr/bin/env bash\nexec /opt/RetroArch.AppImage \"\$@\"\n" > /usr/local/bin/retroarch
        chmod +x /usr/local/bin/retroarch
        echo "RetroArch installed from buildbot (online updater enabled)."
    else
        echo "AppImage not found in archive — trying apt..."
    fi
    rm -rf /tmp/retroarch.7z /tmp/retroarch-extract
else
    echo "Buildbot download failed — trying apt..."
fi
if ! command -v retroarch &>/dev/null; then
    echo "Trying apt repos..."
    apt-get install -y retroarch retroarch-assets && echo "RetroArch installed via apt."
fi'

! [ "$STEAM_INSTALLED" = true ] && \
write_installer_shortcut "STEAM" "Install Steam" \
'dpkg --add-architecture i386 &>/dev/null
apt-get update &>/dev/null
apt-get install -y steam-installer &>/dev/null
apt-get install -y -f &>/dev/null
echo "Steam installed."'

! [[ "${INSTALL_FIREFOX}" =~ ^[Yy] ]] && \
write_installer_shortcut "FIREFOX" "Install Firefox" \
'apt-get install -y firefox &>/dev/null && echo "Firefox installed." || echo "Install failed."'

! [[ "${INSTALL_BRAVE}" =~ ^[Yy] ]] && \
write_installer_shortcut "BRAVE" "Install Brave" \
'curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] \
https://brave-browser-apt-release.s3.brave.com/ stable main" \
    > /etc/apt/sources.list.d/brave-browser-release.list
apt-get update &>/dev/null
apt-get install -y brave-browser &>/dev/null && echo "Brave installed." || echo "Install failed."'

! [[ "${INSTALL_CHROME}" =~ ^[Yy] ]] && \
write_installer_shortcut "CHROME" "Install Google Chrome" \
'wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/chrome.deb
apt-get install -y /tmp/chrome.deb &>/dev/null
rm -f /tmp/chrome.deb
command -v google-chrome &>/dev/null && echo "Chrome installed." || echo "Install failed."'

! [[ "${INSTALL_LIBREOFFICE}" =~ ^[Yy] ]] && \
write_installer_shortcut "LIBREOFFICE" "Install LibreOffice" \
'apt-get install -y libreoffice &>/dev/null && echo "LibreOffice installed." || echo "Install failed."'

! [[ "${INSTALL_VLC}" =~ ^[Yy] ]] && \
write_installer_shortcut "VLC" "Install VLC" \
'apt-get install -y vlc &>/dev/null && echo "VLC installed." || echo "Install failed."'

! [[ "${INSTALL_GIMP}" =~ ^[Yy] ]] && \
write_installer_shortcut "GIMP" "Install GIMP" \
'apt-get install -y gimp &>/dev/null && echo "GIMP installed." || echo "Install failed."'

# Kodi version switcher shortcuts (always present)
cat > /usr/local/bin/install-kodi-ppa.sh <<'EOF'
#!/usr/bin/env bash
echo "Switching to Kodi from Debian repos (v21.x)..."
flatpak list 2>/dev/null | grep -q "tv.kodi.Kodi" && flatpak uninstall -y tv.kodi.Kodi &>/dev/null && echo "Removed Flatpak version."
dpkg --add-architecture i386 &>/dev/null
apt-get update &>/dev/null && apt-get install -y kodi &>/dev/null
apt-get install -y -f &>/dev/null
command -v kodi &>/dev/null && echo "Kodi installed via apt!" || echo "Install failed."
read -p "Press Enter to close..."
EOF
chmod +x /usr/local/bin/install-kodi-ppa.sh

cat > /home/kodi/Desktop/install-kodi-ppa.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Switch to Kodi (apt)
Exec=xfce4-terminal --hold --geometry=120x35 -e "sudo /usr/local/bin/install-kodi-ppa.sh"
Icon=kodi
Terminal=false
X-XFCE-DesktopFile-Trusted=true
EOF

cat > /usr/local/bin/install-kodi-flatpak.sh <<'EOF'
#!/usr/bin/env bash
echo "Switching to Kodi Flatpak (v21.x)..."
dpkg -l | grep -q "^ii  kodi " && apt-get remove -y kodi kodi-bin kodi-data &>/dev/null && apt-get autoremove -y &>/dev/null && echo "Removed apt version."
apt-get install -y flatpak &>/dev/null
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo &>/dev/null
flatpak install -y --noninteractive flathub tv.kodi.Kodi &>/dev/null
flatpak list | grep -q "tv.kodi.Kodi" && echo "Kodi Flatpak installed!" || echo "Install failed."
read -p "Press Enter to close..."
EOF
chmod +x /usr/local/bin/install-kodi-flatpak.sh

cat > /home/kodi/Desktop/install-kodi-flatpak.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Switch to Kodi (Flatpak)
Exec=xfce4-terminal --hold --geometry=120x35 -e "sudo /usr/local/bin/install-kodi-flatpak.sh"
Icon=kodi
Terminal=false
X-XFCE-DesktopFile-Trusted=true
EOF

for f in /home/kodi/Desktop/*.desktop; do
    chmod +x "$f"
    chown kodi:kodi "$f"
done

chown -R kodi:kodi /home/kodi/.config /home/kodi/Desktop

msg_ok "Installer shortcuts done"

# ─────────────────────────────────────────────
# Session environment
# ─────────────────────────────────────────────
cat > /home/kodi/.xprofile <<'EOF'
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000
EOF
chown kodi:kodi /home/kodi/.xprofile

sudo -u kodi XDG_RUNTIME_DIR=/run/user/1000 \
    systemctl --user enable pulseaudio.socket pulseaudio.service &>/dev/null || true

# ─────────────────────────────────────────────
msg_info "Installing HDMI audio fix service"
cat > /usr/local/bin/alsa-hdmi-fix.sh <<'EOF'
#!/usr/bin/env bash
for card in 0 1 2 3 4 5 6 7 8 9; do
    for idx in 0 1 2 3 4 5 6 7 8; do
        amixer -c $card cset "name='IEC958 Playback Switch',index=$idx" on 2>/dev/null || true
    done
done
alsactl store 2>/dev/null || true
EOF
chmod +x /usr/local/bin/alsa-hdmi-fix.sh

cat > /etc/systemd/system/alsa-hdmi-fix.service <<'EOF'
[Unit]
Description=Enable HDMI/DP IEC958 digital audio output
After=alsa-restore.service
Wants=alsa-restore.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/alsa-hdmi-fix.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable alsa-hdmi-fix.service &>/dev/null
msg_ok "HDMI audio fix service installed"

# Start lightdm
# ─────────────────────────────────────────────
msg_info "Starting lightdm"
systemctl enable lightdm &>/dev/null
systemctl restart lightdm &>/dev/null || true
msg_ok "lightdm started"

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo -e "\n${GN}╔═══════════════════════════════════════════════════╗${CL}"
echo -e "${GN}║           xfce-install complete!                  ║${CL}"
echo -e "${GN}╚═══════════════════════════════════════════════════╝${CL}"

echo -e "\n${BL}Session Manager:${CL}"
if [ "$DEFAULT_SESSION" != "Desktop" ] && [ -n "$DEFAULT_SESSION" ]; then
    echo -e "  • Boot: ${GN}black screen → $DEFAULT_SESSION countdown → fullscreen${CL}"
    [[ "$DEFAULT_SESSION" =~ ^(Firefox|Brave|Chrome)$ ]] && \
        echo -e "  • Browser URL: ${GN}$BROWSER_URL${CL}"
else
    echo -e "  • Boot: ${GN}black screen → session menu${CL}"
fi
echo -e "  • After any app exits → session menu reappears (black background)"
echo -e "  • Desktop (XFCE) only loads if explicitly selected"
echo -e "  • Steam runs silently in background when not the active session"

echo -e "\n${BL}Installed:${CL}"
[ "$KODI_INSTALLED"      = true ]       && echo -e "  ${CM} Kodi"
[ "$RETROARCH_INSTALLED" = true ]       && echo -e "  ${CM} RetroArch  (fullscreen — download cores via Online Updater)"
[ "$STEAM_INSTALLED"     = true ]       && echo -e "  ${CM} Steam"
[[ "${INSTALL_FIREFOX}"    =~ ^[Yy] ]] && echo -e "  ${CM} Firefox"
[[ "${INSTALL_BRAVE}"      =~ ^[Yy] ]] && echo -e "  ${CM} Brave"
[[ "${INSTALL_CHROME}"     =~ ^[Yy] ]] && echo -e "  ${CM} Chrome"
[[ "${INSTALL_LIBREOFFICE}" =~ ^[Yy] ]] && echo -e "  ${CM} LibreOffice"
[[ "${INSTALL_VLC}"        =~ ^[Yy] ]] && echo -e "  ${CM} VLC"
[[ "${INSTALL_GIMP}"       =~ ^[Yy] ]] && echo -e "  ${CM} GIMP"

if [ "$SKIP_AUDIO" = false ]; then
    echo -e "\n${BL}Audio:${CL} hw:${SELECTED_CARD},${SELECTED_DEV} — ${SELECTED_DEVICE_NAME}"
else
    echo -e "\n${BL}Audio:${CL} not configured — use ${GN}Configure Audio${CL} from session menu"
fi
echo ""
