# Proxmox Helper

Set of scripts to help in deployment of containers into Proxmox.

based on great work of https://github.com/tteck/Proxmox

# Kodi Media Manager LXC

Containers are created on **Debian 13 (Trixie)** — the host kernel (6.x) plus
`firmware-amd-graphics` and Mesa 25.x from the trixie repos provide full
support for modern AMD iGPUs, including RDNA 3.5 (gfx1150, Radeon 880M/890M).
The iGPU is shared across containers via bind-mounts of `/dev/dri`,
`renderD128` and `/dev/kfd`; only one container owns the physical display
(`/dev/fb0` + `/dev/tty7`) at a time.

## To create a new Proxmox Kodi Media Manager, run the following in the Proxmox Shell.

```yaml
bash -c "$(wget -qLO - https://raw.githubusercontent.com/kjames2001/proxmox-kodi-setup/dev/ct/kodi-v1.sh)"
```
Kodi should be attached to TTY7 console

If kodi is not installed automatically, run in lxc console:

```yaml
bash -c "$(wget -qLO - https://raw.githubusercontent.com/kjames2001/proxmox-kodi-setup/dev/setup/kodi-install.sh)"
```

## To Update Kodi Media Manager:

Run in the LXC console
```yaml
apt update && apt upgrade -y
```
## Note on display access (Xorg on TTY7)

If Xorg fails to start on TTY7 in an unprivileged container it is usually a
device-access-rights issue. Workaround exists but a change on the host
machine is required, so please accept the risk beforehand. Or just use a
privileged container instead. In the Proxmox Shell:
```yaml
chmod 660 /dev/tty7
```

## XFCE Desktop Environment
If you would like a desktop env, select it when running the script.

You will be prompted to set a password for the user "kodi" and asked if you want to install Steam, Firefox, Brave, Chrome, LibreOffice, VLC, GIMP. If you choose not to install, the script will create desktop launchers for all skipped applications. You will also be prompted to select audio device and test if they work.

Kodi is installed from the Debian 13 repositories (v21.x) — the team-xbmc
PPA is no longer used because it has no Debian build. Kodi and RetroArch can
still be switched to Flatpak (v21.x / nightly build) via the desktop
shortcuts.

First boot/shutdown maybe slow, but its only a one time thing.

Shutdown of the lxc is available in kodi or through the desktop shortcut, so that you can access proxmox host shell when needed.

## Bluetooth Setup
If you want to add bluetooth device in Proxmox host, run the following script in proxmox shell:
```
bash -c "$(wget -qLO - https://raw.githubusercontent.com/kjames2001/proxmox-kodi-setup/dev/ct/bluetooth-setup.sh)"
```
