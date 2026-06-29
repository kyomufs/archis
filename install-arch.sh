#!/bin/bash
set -euo pipefail

# =============================================================================
# Arch Linux Installation Script for ASUS TUF Gaming F15 (RTX 3050) + Hyprland
# Auto-mode with configurable flags
# =============================================================================

# --- Configuration (can be overridden via flags) ---
LANG="${LANG:-en_US.UTF-8}"
KEYMAP="${KEYMAP:-us}"
HOSTNAME="${HOSTNAME:-hyprarch}"
USERNAME="${USERNAME:-kyomu}"
DISK="${DISK:-/dev/nvme0n1}"
TIMEZONE="${TIMEZONE:-Europe/Moscow}"

# --- Feature flags (default: enabled) ---
ENABLE_LUKS="${ENABLE_LUKS:-true}"
ENABLE_MULTILIB="${ENABLE_MULTILIB:-true}"
ENABLE_UFW="${ENABLE_UFW:-true}"
ENABLE_SNAPPER="${ENABLE_SNAPPER:-true}"

# --- Passwords (will prompt if not set) ---
ROOT_PASSWORD="${ROOT_PASSWORD:-}"
LUKS_PASSWORD="${LUKS_PASSWORD:-}"
USER_PASSWORD="${USER_PASSWORD:-}"

# --- Logging ---
LOG_FILE="/tmp/arch-install-$(date +%Y%m%d-%H%M%S).log"

log() {
    local level="$1"; shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        INFO)  echo -e "\033[0;32m[INFO]\033[0m $msg" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "\033[0;33m[WARN]\033[0m $msg" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "\033[0;31m[ERROR]\033[0m $msg" | tee -a "$LOG_FILE" >&2 ;;
        *)     echo "[$timestamp] $msg" | tee -a "$LOG_FILE" ;;
    esac
}

error_exit() {
    log ERROR "$*"
    exit 1
}

# --- Parse command line flags ---
parse_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --luks2-skip|--no-luks) ENABLE_LUKS="false"; shift ;;
            --no-multilib) ENABLE_MULTILIB="false"; shift ;;
            --no-ufw) ENABLE_UFW="false"; shift ;;
            --no-snapper) ENABLE_SNAPPER="false"; shift ;;
            --disk) DISK="$2"; shift 2 ;;
            --hostname) HOSTNAME="$2"; shift 2 ;;
            --username) USERNAME="$2"; shift 2 ;;
            *) log WARN "Unknown flag: $1"; shift ;;
        esac
    done
}

# --- Pre-flight checks ---
preflight() {
    log INFO "Checking UEFI mode..."
    [[ -d /sys/firmware/efi/efivars ]] || error_exit "Not booted in UEFI mode"

    log INFO "Checking internet connection..."
    ping -c 1 archlinux.org >/dev/null 2>&1 || error_exit "No internet connection"

    log INFO "Checking required tools..."
    for cmd in sgdisk mkfs.btrfs btrfs pacstrap arch-chroot cryptsetup; do
        command -v "$cmd" >/dev/null 2>&1 || error_exit "Missing required tool: $cmd"
    done

    log INFO "Detecting disks..."
    lsblk -d -o NAME,SIZE,TYPE | grep -q nvme || log WARN "NVMe disk not detected, using $DISK"

    # Get passwords if not set
    [[ -z "$LUKS_PASSWORD" ]] && read -rs -p "LUKS password: " LUKS_PASSWORD && echo
    [[ -z "$USER_PASSWORD" ]] && read -rs -p "User password: " USER_PASSWORD && echo
    [[ -z "$ROOT_PASSWORD" ]] && ROOT_PASSWORD="$USER_PASSWORD"
}

# --- Partition disk (GPT + ESP + LUKS + BTRFS) ---
partition_disk() {
    log INFO "Partitioning $DISK..."

    # Clear disk
    sgdisk --zap-all "$DISK"

    # EFI partition (512M)
    sgdisk -n1:1M:+512M -t1:EF00 "$DISK"

    if [[ "$ENABLE_LUKS" == "true" ]]; then
        # LUKS partition (remaining space)
        sgdisk -n2:0:0 -t2:8300 "$DISK"
        log INFO "Creating LUKS2 container..."
        printf '%s\n' "$LUKS_PASSWORD" | cryptsetup luksFormat --type luks2 "${DISK}2"
        printf '%s\n' "$LUKS_PASSWORD" | cryptsetup open "${DISK}2" cryptroot
        BTRFS_DEV="/dev/mapper/cryptroot"
    else
        sgdisk -n2:0:0 -t2:8300 "$DISK"
        BTRFS_DEV="${DISK}2"
    fi
}

# --- Create BTRFS subvolumes ---
create_btrfs() {
    log INFO "Creating BTRFS filesystem..."
    mkfs.btrfs -f -L "arch" "$BTRFS_DEV"

    log INFO "Creating BTRFS subvolumes..."
    mount "$BTRFS_DEV" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@var
    btrfs subvolume create /mnt/@tmp
    btrfs subvolume create /mnt/@log
    btrfs subvolume create /mnt/@snapshots

    # Enable compression
    btrfs filesystem defrag -r -czstd /mnt/@ 2>/dev/null || true

    umount /mnt
}

# --- Mount filesystems ---
mount_filesystems() {
    log INFO "Mounting filesystems..."
    mount "$BTRFS_DEV" /mnt -o noatime,compress=zstd,subvol=@

    mkdir -p /mnt/{boot,home,var,tmp,.snapshots}
    mount "$BTRFS_DEV" /mnt/home -o noatime,compress=zstd,subvol=@home
    mount "$BTRFS_DEV" /mnt/var -o noatime,compress=zstd,subvol=@var
    mount "$BTRFS_DEV" /mnt/tmp -o noatime,compress=zstd,subvol=@tmp
    mount "$BTRFS_DEV" /mnt/.snapshots -o noatime,compress=zstd,subvol=@snapshots

    EFI_PART="${DISK}p1"
    [[ ! -b "$EFI_PART" ]] && EFI_PART="${DISK}1"
    mount "$EFI_PART" /mnt/boot
}

# --- Install base packages ---
install_base() {
    log INFO "Installing base packages..."

    pacstrap -K /mnt base linux linux-firmware intel-ucode vim nano sudo

    log INFO "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
}

# --- Configure system (chroot) ---
configure_system() {
    log INFO "Configuring system in chroot..."

    # Time
    ln -sf /usr/share/zoneinfo/$TIMEZONE /mnt/etc/localtime
    arch-chroot /mnt hwclock --systohc

    # Locale
    sed -i "s/^#\(en_US.UTF-8 UTF-8\)/\1/" /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen

    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
    echo "KEYMAP=us" > /mnt/etc/vconsole.conf

    # Hostname
    echo "$HOSTNAME" > /mnt/etc/hostname

    # Hosts file
    cat > /mnt/etc/hosts << EOF
127.0.0.1	localhost
::1		localhost
127.0.1.1	$HOSTNAME.localdomain	$HOSTNAME
EOF

    # Root password
    printf 'root:%s\n' "$ROOT_PASSWORD" | arch-chroot /mnt chpasswd

    # User
    arch-chroot /mnt useradd -m -G wheel "$USERNAME"
    printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | arch-chroot /mnt chpasswd
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/etc/sudoers

    # Timezone NTP
    arch-chroot /mnt systemctl enable systemd-timesyncd

    # PAM faillock
    cat >> /mnt/etc/pam.d/system-auth << 'EOF'
auth       required                    pam_faillock.so
auth       sufficient                   pam_unix.so
auth       sufficient                  pam_faillock.so authfail
account     required                   pam_faillock.so
account     required                   pam_unix.so
password    required                   pam_unix.so
session     required                   pam_faillock.so
EOF

    cat > /mnt/etc/security/faillock.conf << EOF
deny = 5
unlock_time = 10
EOF

    # Multilib
    if [[ "$ENABLE_MULTILIB" == "true" ]]; then
        sed -i 's/^#\[multilib\]/\[multilib\]/' /mnt/etc/pacman.conf
    fi

    # ZRAM swap
    arch-chroot /mnt pacman -S --noconfirm zram-generator
    mkdir -p /mnt/etc/systemd
    echo "zram-size = ram / 2" > /mnt/etc/systemd/zram.conf

    log INFO "System configured"
}

# --- Install Hyprland + NVIDIA drivers ---
install_hyprland() {
    log INFO "Installing Hyprland and NVIDIA drivers..."

    local hypr_pkgs=(
        hyprland hyprpaper hypridle hyprlock waybar wofi mako wl-clipboard cliphist
        pipewire pipewire-pulse wireplumber
        networkmanager
        nvidia nvidia-utils nvidia-settings
        libva-nvidia-driver nvidia-prime
        xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
        qt5-wayland qt6-wayland
        noto-fonts noto-fonts-emoji
        brightnessctl playerctl pavucontrol
        foot thunar
        git base-devel
    )

    [[ "$ENABLE_UFW" == "true" ]] && hypr_pkgs+=(ufw)
    [[ "$ENABLE_SNAPPER" == "true" ]] && hypr_pkgs+=(snapper)

    arch-chroot /mnt pacman -S --noconfirm --needed "${hypr_pkgs[@]}"

    # Install yay (AUR helper)
    log INFO "Installing yay AUR helper..."
    arch-chroot /mnt bash -c '
        set -e
        git clone https://aur.archlinux.org/yay.git /tmp/yay
        cd /tmp/yay
        makepkg -si --noconfirm --needed
        rm -rf /tmp/yay
    ' || log WARN "Failed to install yay (continue manually later)"

    # Enable services
    arch-chroot /mnt systemctl enable NetworkManager
    [[ "$ENABLE_UFW" == "true" ]] && arch-chroot /mnt systemctl enable ufw
    [[ "$ENABLE_SNAPPER" == "true" ]] && arch-chroot /mnt systemctl enable snapper-timeline.timer

    log INFO "Hyprland packages installed"
}

# --- Setup systemd-boot ---
setup_bootloader() {
    log INFO "Setting up systemd-boot..."

    arch-chroot /mnt bootctl --path=/boot install

    # UKI configuration
    cat > /mnt/etc/kernel/install.conf << EOF
layout=uki
uki_generator=mkinitcpio
compress_lz4=yes
EOF

    # mkinitcpio for LUKS
    if [[ "$ENABLE_LUKS" == "true" ]]; then
        sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect modconf block keymap encrypt btrfs filesystems)/' /mnt/etc/mkinitcpio.conf
    else
        sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect modconf block btrfs filesystems)/' /mnt/etc/mkinitcpio.conf
    fi

    arch-chroot /mnt mkinitcpio -P

    # Get LUKS partition UUID for boot entry
    local crypt_params=""
    if [[ "$ENABLE_LUKS" == "true" ]]; then
        LUKS_UUID=$(blkid -s UUID -o value "${DISK}2")
        crypt_params="cryptdevice=UUID=${LUKS_UUID}:cryptroot:allow-discards "
    fi

    # Boot entry
    cat > /mnt/boot/loader/entries/arch.conf << EOF
title    Arch Linux
linux    /vmlinuz-linux
initrd   /intel-ucode.img
initrd   /initramfs-linux.img
options  ${crypt_params}rootflags=subvol=@ rw nvidia-drm.modeset=1 intel_iommu=on
EOF

    # Default loader
    cat > /mnt/boot/loader/loader.conf << EOF
default arch.conf
timeout 5
console-mode max
EOF

    log INFO "Bootloader configured"
}

# --- Post-install ---
post_install() {
    log INFO "Creating Hyprland config..."

    arch-chroot /mnt -u "$USERNAME" bash << HYPRCONF
set -e
mkdir -p ~/.config/hypr
mkdir -p ~/.config/hypr/hypridle

# Hyprland config (Lua syntax v0.55+)
cat > ~/.config/hypr/hyprland.lua << 'EOF'
-- Environment variables for NVIDIA Optimus
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("AQ_DRM_DEVICES", "/dev/dri/card1:/dev/dri/card0")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("GTK_THEME", "Adwaita:dark")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("QT_QPA_PLATFORM", "wayland")

-- Monitor configuration
hl.monitor({
    name = "eDP-1",
    mode = "1920x1080@144",
    position = "0x0",
    scale = 1
})

-- Input configuration
hl.input({
    kb_layout = "us,ru",
    kb_options = "grp:win_space_toggle"
})

-- Autostart
hl.on("hyprland.start", function()
    hl.exec_cmd("waybar &")
    hl.exec_cmd("hyprpaper &")
    hl.exec_cmd("mako &")
    hl.exec_cmd("wl-paste --type text --watch cliphist store &")
    hl.exec_cmd("wl-paste --type image --watch cliphist store &")
end)

-- Keybindings
hl.bind("SUPER+RETURN", hl.dsp.exec_cmd("foot"))
hl.bind("SUPER+E", hl.dsp.exec_cmd("thunar"))
hl.bind("SUPER+R", hl.dsp.exec_cmd("wofi --show drun"))
hl.bind("SUPER+V", hl.dsp.exec_cmd("cliphist list | wofi --dmenu | cliphist decode | wl-copy"))
hl.bind("SUPER+L", hl.dsp.exec_cmd("hyprlock"))
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("pamixer -i 5"))
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("pamixer -d 5"))
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("pamixer -t"))
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl s +5%"))
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 5%-"))
EOF

# Hypridle config
cat > ~/.config/hypr/hypridle.conf << 'EOF'
general {
    lock_cmd = pidof hyprlock || hyprlock
}
listener {
    timeout = 300
    on_timeout = loginctl lock-session
}
listener {
    timeout = 600
    on_timeout = systemctl suspend
}
EOF

# Waybar config
mkdir -p ~/.config/waybar
cat > ~/.config/waybar/config << 'EOF'
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "modules-left": ["custom/menu", "wlr/workspaces"],
    "modules-right": ["pulseaudio", "network", "cpu", "memory", "clock"]
}
EOF

# Mako config
cat > ~/.config/mako/config << 'EOF'
font=monospace 10
background=#1e1e2eDD
border_color=#fab387
border_size=2
text_color=#cdd6f4
padding=8
margin=10
anchor=top-right
EOF
HYPRCONF

    # Snapper config if enabled
    if [[ "$ENABLE_SNAPPER" == "true" ]]; then
        log INFO "Configuring snapper..."
        arch-chroot /mnt snapper -c root create-config /
        arch-chroot /mnt snapper -c home create-config /home
        sed -i 's/^TIMELINE_LIMIT_HOURLY=".*"$/TIMELINE_LIMIT_HOURLY="10"/' /mnt/etc/snapper/root/config || true
    fi

    log INFO "Installation complete! Log saved to $LOG_FILE"

    # Close LUKS
    if [[ "$ENABLE_LUKS" == "true" ]]; then
        log INFO "Closing LUKS container..."
        cryptsetup close cryptroot
    fi
}

# --- Main ---
main() {
    parse_flags "$@"
    log INFO "Starting Arch Linux installation for $(hostname 2>/dev/null || echo 'ASUS RTX 3050')..."

    preflight
    partition_disk
    create_btrfs
    mount_filesystems
    install_base
    configure_system
    install_hyprland
    setup_bootloader
    post_install

    log INFO "Ready to reboot. Run 'reboot' to start."
}

main "$@"