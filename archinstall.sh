#!/usr/bin/env bash
# Arch Linux automated installer - single modular script
# Based on arhcinst.md template
set -euo pipefail

################################################################################
# CONFIGURATION & DEFAULTS
################################################################################

# Directories
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
MNT="/mnt"

# Disk & Partitioning
DISK="${DISK:-/dev/nvme0n1}"
LUKS_NAME="cryptlvm"
VG_NAME="vg0"
LV_NAME="root"

# System Localization
KEYMAP="us"
LOCALE="en_US.UTF-8"
TIMEZONE="Europe/Moscow"
HOSTNAME="hyprarch"

# User
USER_NAME="kyomu"
ROOT_PASS="root123"
USER_PASS="user123"
LUKS_PASS="luks123"

# Features
ZRAM_ALGORITHM="zstd"
FAILLOCK_DENY=5
FAILLOCK_UNLOCK_TIME=10

# Packages (from arhcinst.md)
PACKAGES=(
  # Base
  base base-devel linux linux-headers linux-firmware dkms
  sudo git man-db man-pages

  # Filesystems & Encryption
  btrfs-progs lvm2 cryptsetup snapper snap-pac

  # Bootloader
  efibootmgr

  # Network
  networkmanager iwd

  # Bluetooth & Audio
  bluez bluez-utils blueman
  pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber pavucontrol playerctl
  sof-firmware

  # Power & Hardware
  power-profiles-daemon brightnessctl

  # Security
  ufw

  # Fonts
  noto-fonts

  # Hyprland Desktop
  hyprland hyprlock hypridle hyprpaper hyprpicker hyprsunset hyprpolkitagent
  polkit seatd

  # Wayland Support
  xorg-xwayland qt5-wayland qt6-wayland wl-clipboard
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-utils egl-wayland

  # Terminal & Editors
    kitty neovim nano

  # File Manager & Archive
    dolphin 7zip tar gzip pigz

  # Theming
  nwg-look qt5ct qt6ct

  # Screenshots
  grim slurp

  # Applications
    firefox gwenview btop openssh gnome-keyring

  # GPU Support (NVIDIA + Intel)
  nvidia-open-dkms nvidia-utils nvidia-settings lib32-nvidia-utils libva-nvidia-driver
  nvidia-prime switcheroo-control acpi_call
  mesa vulkan-intel intel-media-driver lib32-mesa lib32-vulkan-intel intel-ucode
    mesa-utils vulkan-tools

  # zram
  zram-generator
)

# Runtime
DRY_RUN=0
ASSUME_YES=0
VERBOSE=0

[[ $VERBOSE -eq 1 ]] && set -x

################################################################################
# LOGGING & OUTPUT
################################################################################

log_info() {
    echo -e "\033[34m[i]\033[0m $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "\033[32m[✓]\033[0m $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "\033[33m[!]\033[0m $*" | tee -a "$LOG_FILE" >&2
}

log_error() {
    echo -e "\033[31m[x]\033[0m $*" | tee -a "$LOG_FILE" >&2
}

log_header() {
    echo -e "\033[1m\033[34m==> $*\033[0m" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo -e "\033[36m[DEBUG]\033[0m $*" | tee -a "$LOG_FILE"
    else
        echo "[DEBUG] $*" >> "$LOG_FILE"
    fi
}

log_cmd() {
    echo -e "\033[37m[CMD]\033[0m $*" | tee -a "$LOG_FILE"
}

log_result() {
    local status=$?
    if [[ $status -eq 0 ]]; then
        log_success "$1"
    else
        log_error "$1 (exit code: $status)"
        return "$status"
    fi
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

log_config() {
    log_header "Installation Configuration"
    log_debug "DISK: $DISK"
    log_debug "LUKS_NAME: $LUKS_NAME"
    log_debug "VG_NAME: $VG_NAME"
    log_debug "LV_NAME: $LV_NAME"
    log_debug "KEYMAP: $KEYMAP"
    log_debug "LOCALE: $LOCALE"
    log_debug "TIMEZONE: $TIMEZONE"
    log_debug "HOSTNAME: $HOSTNAME"
    log_debug "USER_NAME: $USER_NAME"
    log_debug "ZRAM_ALGORITHM: $ZRAM_ALGORITHM"
    log_debug "FAILLOCK_DENY: $FAILLOCK_DENY"
    log_debug "FAILLOCK_UNLOCK_TIME: $FAILLOCK_UNLOCK_TIME"
    log_debug "MNT: $MNT"
    log_debug "LOG_FILE: $LOG_FILE"
    log_debug "DRY_RUN: $DRY_RUN"
    log_debug "ASSUME_YES: $ASSUME_YES"
}

confirm() {
    local msg="$1"
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: assuming yes for: $msg"
        return 0
    fi
    if [[ $ASSUME_YES -eq 1 ]]; then
        log_info "ASSUME-YES: proceeding without prompt for: $msg"
        return 0
    fi
    read -rp "$msg [y/N]: " yn
    [[ "$yn" =~ [Yy] ]]
}

################################################################################
# PREFLIGHT CHECKS
################################################################################

preflight_checks() {
    log_header "Running preflight checks"

    local required_cmds=(
        pacman pacstrap genfstab mkinitcpio arch-chroot
        cryptsetup lvm pvcreate vgcreate lvcreate
        parted mount umount btrfs mkfs.btrfs mkfs.fat
        lsblk bootctl efibootmgr systemctl timedatectl
    )

    log_info "Checking for required commands..."
    local missing=0
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_warn "Missing: $cmd"
            missing=1
        else
            log_debug "Found: $cmd"
        fi
    done

    if [[ $missing -eq 1 ]]; then
        log_error "Some required commands are missing"
        return 1
    fi
    log_success "All required commands found"

    log_info "Checking system mode..."
    if [[ ! -d /sys/firmware/efi ]]; then
        log_warn "Not booted in UEFI mode (expected for systemd-boot)"
    else
        log_success "UEFI boot detected"
    fi

    log_info "Checking target disk..."
    if [[ ! -e "$DISK" ]]; then
        log_error "Disk $DISK not found"
        return 1
    fi
    log_success "Disk $DISK found"

    log_debug "Disk information:"
    lsblk "$DISK" 2>&1 | tee -a "$LOG_FILE" || true

    log_success "Preflight checks passed"
}

################################################################################
# DISK OPERATIONS
################################################################################

partition_suffix() {
    local disk="$1"
    local bn=$(basename "$disk")
    case "$bn" in
        nvme*|mmcblk*|loop*) echo "p" ;;
        *) echo "" ;;
    esac
}

cleanup_target() {
    if mountpoint -q "$MNT" 2>/dev/null; then
        umount -R "$MNT" 2>/dev/null || true
    fi

    if cryptsetup status "$LUKS_NAME" &>/dev/null; then
        vgchange -an "$VG_NAME" &>/dev/null || true
        cryptsetup close "$LUKS_NAME" &>/dev/null || true
    fi
}

prepare_pacman_config() {
    local config_dir
    config_dir="$(mktemp -d)"
    local config_file="$config_dir/pacman.conf"
    local mirrorlist_file="$config_dir/mirrorlist"

    cp /etc/pacman.conf "$config_file"

    log_info "Preparing temporary pacman config for installation..."
    if command -v reflector &>/dev/null; then
        log_cmd "reflector --latest 20 --protocol https --sort rate --save $mirrorlist_file"
        if ! reflector --latest 20 --protocol https --sort rate --save "$mirrorlist_file" 2>&1 | tee -a "$LOG_FILE"; then
            log_warn "reflector failed, falling back to existing mirrorlist"
            awk '/^Server=/' /etc/pacman.d/mirrorlist > "$mirrorlist_file"
        fi
    else
        log_warn "reflector not available, using sanitized host mirrorlist"
        awk '/^Server=/' /etc/pacman.d/mirrorlist > "$mirrorlist_file"
    fi

    if grep -q '^#Color' "$config_file"; then
        sed -i 's/^#Color/Color/' "$config_file"
    elif ! grep -q '^Color' "$config_file"; then
        printf '\nColor\n' >> "$config_file"
    fi

    if grep -q '^#\[multilib\]' "$config_file"; then
        sed -i '/^#\[multilib\]/s/^#//' "$config_file"
        sed -i '/^\[multilib\]/{n; s/^#Include/Include/}' "$config_file"
    elif ! grep -q '^\[multilib\]' "$config_file"; then
        cat >> "$config_file" <<EOF

[multilib]
Include = $mirrorlist_file
EOF
    fi

    sed -i "s|^#Include = /etc/pacman.d/mirrorlist|Include = $mirrorlist_file|" "$config_file"
    sed -i "s|^Include = /etc/pacman.d/mirrorlist|Include = $mirrorlist_file|" "$config_file"
}

partition_disk() {
    log_header "Partitioning disk: $DISK"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: would partition $DISK (EFI 550M + LVM rest)"
        return 0
    fi

    log_debug "Checking if disk $DISK exists..."
    if [[ ! -e "$DISK" ]]; then
        log_error "Disk $DISK not found"
        return 1
    fi
    log_success "Disk $DISK found"

    log_debug "Current partition layout before modification:"
    lsblk "$DISK" 2>&1 | tee -a "$LOG_FILE" || true

    log_warn "This will DESTROY all data on $DISK"
    if ! confirm "Proceed with partitioning?"; then
        log_info "Aborted"
        return 1
    fi

    log_cmd "parted --script $DISK mklabel gpt"
    parted --script "$DISK" mklabel gpt 2>&1 | tee -a "$LOG_FILE"

    log_cmd "parted --script $DISK mkpart primary fat32 1MiB 551MiB"
    parted --script "$DISK" mkpart primary fat32 1MiB 551MiB 2>&1 | tee -a "$LOG_FILE"

    log_cmd "parted --script $DISK set 1 esp on"
    parted --script "$DISK" set 1 esp on 2>&1 | tee -a "$LOG_FILE"

    log_cmd "parted --script $DISK mkpart primary 551MiB 100%"
    parted --script "$DISK" mkpart primary 551MiB 100% 2>&1 | tee -a "$LOG_FILE"

    log_debug "Partition layout after modification:"
    lsblk "$DISK" 2>&1 | tee -a "$LOG_FILE" || true

    log_success "Partitions created"
}

setup_luks_lvm() {
    local efi_part="${DISK}$(partition_suffix "$DISK")1"
    local lvm_part="${DISK}$(partition_suffix "$DISK")2"

    log_header "Setting up LUKS encryption and LVM"
    log_debug "EFI partition: $efi_part"
    log_debug "LVM partition: $lvm_part"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: would encrypt $lvm_part and create LVM volume group"
        return 0
    fi

    log_debug "Verifying partitions exist..."
    for part in "$efi_part" "$lvm_part"; do
        if [[ ! -e "$part" ]]; then
            log_error "Partition $part not found"
            return 1
        fi
        log_success "Found partition: $part"
    done

    log_info "Creating LUKS container on $lvm_part (automated passphrase)"
    log_debug "Using automated LUKS passphrase from configuration"
    log_cmd "printf '***' | cryptsetup --batch-mode luksFormat --key-file - $lvm_part"
    printf '%s' "$LUKS_PASS" | cryptsetup --batch-mode luksFormat --key-file - "$lvm_part" 2>&1 | tee -a "$LOG_FILE"
    log_result "LUKS format completed"

    log_cmd "printf '***' | cryptsetup open --key-file - $lvm_part $LUKS_NAME"
    printf '%s' "$LUKS_PASS" | cryptsetup open --key-file - "$lvm_part" "$LUKS_NAME" 2>&1 | tee -a "$LOG_FILE"
    log_result "LUKS container opened"

    log_debug "Mapped device: /dev/mapper/$LUKS_NAME"
    if [[ -e "/dev/mapper/$LUKS_NAME" ]]; then
        log_success "LUKS device ready"
    else
        log_error "LUKS device /dev/mapper/$LUKS_NAME not found"
        return 1
    fi

    log_cmd "pvcreate /dev/mapper/$LUKS_NAME"
    pvcreate "/dev/mapper/$LUKS_NAME" 2>&1 | tee -a "$LOG_FILE"
    log_result "Physical volume created"

    log_cmd "vgcreate $VG_NAME /dev/mapper/$LUKS_NAME"
    vgcreate "$VG_NAME" "/dev/mapper/$LUKS_NAME" 2>&1 | tee -a "$LOG_FILE"
    log_result "Volume group created"

    log_cmd "lvcreate -l 100%FREE -n $LV_NAME $VG_NAME"
    lvcreate -l 100%FREE -n "$LV_NAME" "$VG_NAME" 2>&1 | tee -a "$LOG_FILE"
    log_result "Logical volume created"

    log_debug "LVM status:"
    pvdisplay 2>&1 | tee -a "$LOG_FILE" || true
    vgdisplay 2>&1 | tee -a "$LOG_FILE" || true
    lvdisplay 2>&1 | tee -a "$LOG_FILE" || true

    log_success "LUKS+LVM ready: /dev/$VG_NAME/$LV_NAME"
}

format_filesystems() {
    local efi_part="${DISK}$(partition_suffix "$DISK")1"
    local lv_path="/dev/$VG_NAME/$LV_NAME"

    log_header "Formatting and mounting filesystems"
    log_debug "EFI partition: $efi_part"
    log_debug "LVM device: $lv_path"
    log_debug "Mount point: $MNT"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: would format EFI and btrfs, create subvolumes"
        return 0
    fi

    log_cmd "mkfs.fat -F32 $efi_part"
    mkfs.fat -F32 "$efi_part" 2>&1 | tee -a "$LOG_FILE"
    log_result "EFI filesystem created"

    log_cmd "mkfs.btrfs -f $lv_path"
    mkfs.btrfs -f "$lv_path" 2>&1 | tee -a "$LOG_FILE"
    log_result "Btrfs filesystem created"

    log_debug "Creating mount point: $MNT"
    mkdir -p "$MNT"

    log_cmd "mount -t btrfs $lv_path $MNT"
    if ! mount -t btrfs "$lv_path" "$MNT" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Initial btrfs mount failed"
        return 1
    fi
    log_result "Root mounted"

    log_info "Creating btrfs subvolumes..."
    log_cmd "btrfs subvolume create $MNT/@"
    btrfs subvolume create "$MNT"/@ 2>&1 | tee -a "$LOG_FILE"
    log_success "Subvolume @ created"

    log_cmd "btrfs subvolume create $MNT/@home"
    btrfs subvolume create "$MNT"/@home 2>&1 | tee -a "$LOG_FILE"
    log_success "Subvolume @home created"

    log_cmd "btrfs subvolume create $MNT/@snapshots"
    btrfs subvolume create "$MNT"/@snapshots 2>&1 | tee -a "$LOG_FILE"
    log_success "Subvolume @snapshots created"

    log_debug "Current subvolumes:"
    btrfs subvolume list "$MNT" 2>&1 | tee -a "$LOG_FILE" || true

    local root_subvol_id
    root_subvol_id=$(btrfs subvolume list "$MNT" | awk '$NF == "@" { print $2; exit }')
    if [[ -z "$root_subvol_id" ]]; then
        log_error "Could not determine root subvolume ID"
        return 1
    fi

    log_cmd "btrfs subvolume set-default $root_subvol_id $MNT"
    if ! btrfs subvolume set-default "$root_subvol_id" "$MNT" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to set default btrfs subvolume"
        return 1
    fi

    log_cmd "umount $MNT"
    if ! umount "$MNT" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to unmount $MNT"
        return 1
    fi
    log_result "Root unmounted for remount with subvolume options"

    log_info "Remounting with compression and default subvolume..."
    log_cmd "mount -o noatime,compress=zstd $lv_path $MNT"
    if ! mount -o noatime,compress=zstd "$lv_path" "$MNT" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Root remount failed"
        return 1
    fi
    log_result "Root remounted"

    mkdir -p "$MNT/home"
    log_cmd "mount -o noatime,compress=zstd,subvol=@home $lv_path $MNT/home"
    if ! mount -o noatime,compress=zstd,subvol=@home "$lv_path" "$MNT/home" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Home remount failed"
        return 1
    fi
    log_result "Home mounted with subvol=@home"

    mkdir -p "$MNT/.snapshots"
    log_cmd "mount -o noatime,compress=zstd,subvol=@snapshots $lv_path $MNT/.snapshots"
    if ! mount -o noatime,compress=zstd,subvol=@snapshots "$lv_path" "$MNT/.snapshots" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Snapshots remount failed"
        return 1
    fi
    log_result "Snapshots mounted with subvol=@snapshots"

    mkdir -p "$MNT/boot"
    log_cmd "mount $efi_part $MNT/boot"
    if ! mount "$efi_part" "$MNT/boot" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "EFI mount failed"
        return 1
    fi
    log_result "EFI mounted at /boot"

    log_debug "Final mount status:"
    mount | grep "$MNT" | tee -a "$LOG_FILE" || true

    log_success "Filesystems mounted at $MNT"
}

generate_fstab() {
    log_header "Generating /etc/fstab"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: would generate fstab"
        return 0
    fi

    if ! mountpoint -q "$MNT"; then
        log_error "$MNT is not a mountpoint"
        return 1
    fi

    mkdir -p "$MNT/etc"

    log_cmd "genfstab -U $MNT"
    log_info "Generating fstab with UUIDs..."
    genfstab -U "$MNT" > "$MNT/etc/fstab.tmp" 2>&1
    tee -a "$LOG_FILE" < "$MNT/etc/fstab.tmp" > /dev/null

    log_debug "Removing swap entries (if any)..."
    sed '/swap/d' "$MNT/etc/fstab.tmp" > "$MNT/etc/fstab"
    rm "$MNT/etc/fstab.tmp"

    log_debug "Generated /etc/fstab content:"
    cat "$MNT/etc/fstab" | tee -a "$LOG_FILE"

    log_success "fstab generated"
}

################################################################################
# PACKAGE MANAGEMENT
################################################################################

configure_pacman() {
    log_header "Configuring pacman"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: would enable Color and multilib"
        return 0
    fi

    local target_root="${1:-$MNT}"
    local pacman_conf="$target_root/etc/pacman.conf"

    if [[ ! -f "$pacman_conf" ]]; then
        log_error "pacman.conf not found at $pacman_conf"
        return 1
    fi

    if grep -q '^#Color' "$pacman_conf"; then
        sed -i 's/^#Color/Color/' "$pacman_conf"
    elif ! grep -q '^Color' "$pacman_conf"; then
        printf '\nColor\n' >> "$pacman_conf"
    fi

    if grep -q '^#\[multilib\]' "$pacman_conf"; then
        sed -i '/^#\[multilib\]/s/^#//' "$pacman_conf"
        # Also uncomment the Include line right after [multilib]
        sed -i '/^\[multilib\]/{n; s/^#Include/Include/}' "$pacman_conf"
    fi

    if grep -q '^#Include = /etc/pacman.d/mirrorlist' "$pacman_conf"; then
        sed -i 's|^#Include = /etc/pacman.d/mirrorlist|Include = /etc/pacman.d/mirrorlist|' "$pacman_conf"
    elif ! grep -q '^Include = /etc/pacman.d/mirrorlist' "$pacman_conf" && grep -q '^\[multilib\]' "$pacman_conf"; then
        printf 'Include = /etc/pacman.d/mirrorlist\n' >> "$pacman_conf"
    fi

    log_success "pacman configured"
}

configure_mirrors() {
    log_header "Configuring mirrors"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: would update mirrorlist with reflector"
        return 0
    fi

    local mirrorlist_path="${1:-/etc/pacman.d/mirrorlist}"

    if command -v reflector &>/dev/null; then
        log_cmd "reflector --latest 20 --protocol https --sort rate --save $mirrorlist_path"
        if reflector --latest 20 --protocol https --sort rate --save "$mirrorlist_path" 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Mirrorlist updated"
            return 0
        fi
        log_warn "reflector failed, falling back to sanitized mirrorlist"
    else
        log_warn "reflector not available, using sanitized mirrorlist"
    fi

    awk '/^Server=/' /etc/pacman.d/mirrorlist > "$mirrorlist_path"
    log_success "Mirrorlist updated"
}

install_base_system() {
    log_header "Installing base system with pacstrap"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: would run pacstrap"
        return 0
    fi

    local pacman_config_dir pacman_conf_file mirrorlist_file pacman_wrapper_dir
    pacman_config_dir="$(mktemp -d)"
    trap '[[ -d "${pacman_config_dir:-}" ]] && rm -rf "$pacman_config_dir"' RETURN

    pacman_conf_file="$pacman_config_dir/pacman.conf"
    mirrorlist_file="$pacman_config_dir/mirrorlist"
    pacman_wrapper_dir="$pacman_config_dir/bin"
    cp /etc/pacman.conf "$pacman_conf_file"

    configure_mirrors "$mirrorlist_file"

    if grep -q '^#Color' "$pacman_conf_file"; then
        sed -i 's/^#Color/Color/' "$pacman_conf_file"
    elif ! grep -q '^Color' "$pacman_conf_file"; then
        printf '\nColor\n' >> "$pacman_conf_file"
    fi

    if grep -q '^#\[multilib\]' "$pacman_conf_file"; then
        sed -i '/^#\[multilib\]/s/^#//' "$pacman_conf_file"
        sed -i '/^\[multilib\]/{n; s/^#Include/Include/}' "$pacman_conf_file"
    elif ! grep -q '^\[multilib\]' "$pacman_conf_file"; then
        cat >> "$pacman_conf_file" <<EOF

[multilib]
Include = $mirrorlist_file
EOF
    fi

    sed -i "s|^#Include = /etc/pacman.d/mirrorlist|Include = $mirrorlist_file|" "$pacman_conf_file"
    sed -i "s|^Include = /etc/pacman.d/mirrorlist|Include = $mirrorlist_file|" "$pacman_conf_file"

    mkdir -p "$MNT/var/cache/pacman/pkg"
    # Clear potentially corrupted packages from previous runs on target
    log_info "Clearing package cache to avoid stale/corrupted packages..."
    rm -f "$MNT/var/cache/pacman/pkg"/*.pkg.tar.* 2>/dev/null || true
    # Free up live-ISO RAM by clearing its pacman cache
    # (without -c, pacstrap downloads directly to $MNT, not the live ISO tmpfs)
    log_info "Freeing live ISO package cache from RAM..."
    rm -f /var/cache/pacman/pkg/*.pkg.tar.* 2>/dev/null || true

    # Filter available packages
    log_info "Filtering available packages..."
    local available=()
    local skipped=()
    for pkg in "${PACKAGES[@]}"; do
        if pacman --config "$pacman_conf_file" -Si "$pkg" &>/dev/null; then
            available+=("$pkg")
        else
            skipped+=("$pkg")
        fi
    done

    log_debug "Available packages: ${#available[@]}"
    log_debug "Skipped packages: ${#skipped[@]}"

    if [[ ${#skipped[@]} -gt 0 ]]; then
        log_warn "Skipped (not in repos): ${skipped[*]}"
    fi

    if [[ ${#available[@]} -eq 0 ]]; then
        log_error "No packages available"
        return 1
    fi

    log_cmd "pacstrap $MNT ${available[*]}"
    log_info "Running pacstrap with ${#available[@]} packages..."
    local pacstrap_attempts=3
    local pacstrap_ok=0
    for attempt in $(seq 1 "$pacstrap_attempts"); do
        if pacstrap -K -C "$pacman_conf_file" "$MNT" "${available[@]}" 2>&1 | tee -a "$LOG_FILE"; then
            pacstrap_ok=1
            break
        fi
        if [[ $attempt -lt $pacstrap_attempts ]]; then
            log_warn "pacstrap attempt $attempt failed, retrying in 5s..."
            sleep 5
            # Remove any corrupted cached packages before retry
            rm -f "$MNT/var/cache/pacman/pkg"/*.pkg.tar.* 2>/dev/null || true
        fi
    done
    if [[ $pacstrap_ok -eq 0 ]]; then
        log_error "Failed to install base system"
        return 1
    fi
    log_success "Base system installed"

    configure_pacman "$MNT"

    log_debug "Installed packages:"
    arch-chroot "$MNT" pacman -Q 2>&1 | tee -a "$LOG_FILE" | wc -l | while read -r count; do log_debug "Total packages installed: $count"; done
}

################################################################################
# SYSTEM CONFIGURATION
################################################################################

configure_locale() {
    log_header "Configuring locale and timezone"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: would set locale and timezone"
        return 0
    fi

    echo "LANG=$LOCALE" > "$MNT/etc/locale.conf"
    arch-chroot "$MNT" /bin/bash -c "sed -i '/^$LOCALE UTF-8/d' /etc/locale.gen && echo '$LOCALE UTF-8' >> /etc/locale.gen && locale-gen"
    arch-chroot "$MNT" /bin/bash -c "ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime"
    arch-chroot "$MNT" /bin/bash -c "hwclock --systohc"

    # Set keymap in live environment
    if [[ $DRY_RUN -eq 0 ]]; then
        loadkeys "$KEYMAP" 2>/dev/null || true
    fi

    log_success "Locale configured"
}

configure_hostname() {
    log_header "Setting hostname"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: would set hostname to $HOSTNAME"
        return 0
    fi

    echo "$HOSTNAME" > "$MNT/etc/hostname"
    cat > "$MNT/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

    log_success "Hostname set"
}

################################################################################
# BOOTLOADER & INITRAMFS
################################################################################

configure_mkinitcpio() {
    log_header "Configuring mkinitcpio for LUKS+LVM"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: would configure mkinitcpio hooks"
        return 0
    fi

    if [[ ! -f "$MNT/etc/mkinitcpio.conf" ]]; then
        log_error "mkinitcpio.conf not found in target system"
        return 1
    fi

    log_debug "Patching mkinitcpio.conf hooks and compression..."
    sed -i 's|^HOOKS=.*|HOOKS=(base udev autodetect modconf block keyboard keymap consolefont encrypt lvm2 filesystems fsck)|' "$MNT/etc/mkinitcpio.conf"
    sed -i 's|^#COMPRESSION="zstd"|COMPRESSION="zstd"|' "$MNT/etc/mkinitcpio.conf"
    sed -i 's|^COMPRESSION=.*|COMPRESSION="zstd"|' "$MNT/etc/mkinitcpio.conf"

    log_debug "Content of mkinitcpio.conf:"
    cat "$MNT/etc/mkinitcpio.conf" | tee -a "$LOG_FILE"

    log_cmd "arch-chroot $MNT mkinitcpio -P"
    arch-chroot "$MNT" /bin/bash -c "mkinitcpio -P" 2>&1 | tee -a "$LOG_FILE"
    log_result "mkinitcpio configured and initramfs built"

    log_success "mkinitcpio configured"
}

install_bootloader() {
    log_header "Installing systemd-boot"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: would install bootloader and create loader entry"
        return 0
    fi

    log_cmd "arch-chroot $MNT bootctl --path=/boot install"
    arch-chroot "$MNT" bootctl --path=/boot install 2>&1 | tee -a "$LOG_FILE"
    log_result "systemd-boot installed"

    log_info "Getting LUKS UUID for boot parameters..."
    local luks_part="${DISK}$(partition_suffix "$DISK")2"
    local luks_uuid=$(cryptsetup luksUUID "$luks_part")
    log_debug "LUKS UUID: $luks_uuid"

    mkdir -p "$MNT/boot/loader/entries"

    log_debug "Creating bootloader entry with encrypted root parameters..."
    cat > "$MNT/boot/loader/entries/arch.conf" <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options cryptdevice=UUID=$luks_uuid:$LUKS_NAME root=/dev/$VG_NAME/$LV_NAME rootflags=subvol=@ rw nvidia-drm.modeset=1
EOF

    log_debug "Bootloader entry content:"
    cat "$MNT/boot/loader/entries/arch.conf" | tee -a "$LOG_FILE"

    log_debug "Bootloader status:"
    arch-chroot "$MNT" bootctl status 2>&1 | tee -a "$LOG_FILE" || true

    log_success "Bootloader installed"
}

################################################################################
# USER & SECURITY
################################################################################

setup_users() {
    log_header "Setting up root and user accounts"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: would create root and user $USER_NAME"
        return 0
    fi

    log_info "Setting root password..."
    log_cmd "echo 'root:***' | arch-chroot $MNT chpasswd"
    arch-chroot "$MNT" /bin/bash -c "echo 'root:$ROOT_PASS' | chpasswd" 2>&1 | tee -a "$LOG_FILE"
    log_result "Root password set"

    if arch-chroot "$MNT" /usr/bin/id -u "$USER_NAME" &>/dev/null; then
        log_warn "User $USER_NAME already exists, skipping useradd"
    else
        log_info "Creating user account: $USER_NAME"
        log_cmd "arch-chroot $MNT useradd -m -G wheel -s /bin/bash $USER_NAME"
        arch-chroot "$MNT" /usr/bin/useradd -m -G wheel -s /bin/bash "$USER_NAME" 2>&1 | tee -a "$LOG_FILE"
        log_result "User $USER_NAME created"
    fi

    log_info "Setting user password..."
    log_cmd "echo '$USER_NAME:***' | arch-chroot $MNT chpasswd"
    arch-chroot "$MNT" /bin/bash -c "echo '$USER_NAME:$USER_PASS' | chpasswd" 2>&1 | tee -a "$LOG_FILE"
    log_result "User password set"

    log_info "Configuring sudo for wheel group..."
    cat > "$MNT/etc/sudoers.d/99_wheel" <<'EOF'
%wheel ALL=(ALL) ALL
EOF
    chmod 0440 "$MNT/etc/sudoers.d/99_wheel"
    log_result "Sudo configured"

    log_debug "User/group verification:"
    arch-chroot "$MNT" id "$USER_NAME" 2>&1 | tee -a "$LOG_FILE" || true
    arch-chroot "$MNT" getent group wheel 2>&1 | tee -a "$LOG_FILE" || true

    log_success "Users configured"
}

setup_pam_faillock() {
    log_header "Configuring pam_faillock"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: would configure faillock with deny=$FAILLOCK_DENY unlock_time=$FAILLOCK_UNLOCK_TIME"
        return 0
    fi

    mkdir -p "$MNT/etc/security"
    cat > "$MNT/etc/security/faillock.conf" <<EOF
deny = $FAILLOCK_DENY
unlock_time = $FAILLOCK_UNLOCK_TIME
fail_interval = 900
EOF

    log_success "pam_faillock configured"
}

################################################################################
# ADVANCED FEATURES
################################################################################

setup_zram() {
    log_header "Configuring zram swap"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: would configure zram with $ZRAM_ALGORITHM compression"
        return 0
    fi

    mkdir -p "$MNT/etc/systemd"
    cat > "$MNT/etc/systemd/zram-generator.conf" <<EOF
[zram0]
zram-size = ram / 2
compression-algorithm = $ZRAM_ALGORITHM
swap-priority = 100
EOF

    log_cmd "arch-chroot $MNT systemctl enable systemd-zram-setup@zram0.service"
    arch-chroot "$MNT" systemctl enable systemd-zram-setup@zram0.service 2>&1 | tee -a "$LOG_FILE" || true

    log_success "zram configured"
}

setup_snapper() {
    log_header "Configuring snapper for btrfs snapshots"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: would configure snapper"
        return 0
    fi

    if ! findmnt -no FSTYPE "$MNT" | grep -qx btrfs; then
        log_error "$MNT is not mounted as btrfs"
        return 1
    fi

    log_debug "Btrfs default subvolume:"
    btrfs subvolume get-default "$MNT" 2>&1 | tee -a "$LOG_FILE" || true

    if mountpoint -q "$MNT/.snapshots"; then
        umount "$MNT/.snapshots" || true
    fi
    rm -rf "$MNT/.snapshots" || true

    log_cmd "arch-chroot $MNT snapper -c root create-config /"
    if ! arch-chroot "$MNT" /bin/bash -c "snapper -c root create-config /" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to create snapper root config"
        return 1
    fi

    arch-chroot "$MNT" btrfs subvolume delete /.snapshots || true
    mkdir -p "$MNT/.snapshots"
    mount -a --target "$MNT/.snapshots" || mount -o noatime,compress=zstd,subvol=@snapshots "/dev/$VG_NAME/$LV_NAME" "$MNT/.snapshots" || true

    log_cmd "arch-chroot $MNT snapper -c home create-config /home"
    if ! arch-chroot "$MNT" /bin/bash -c "snapper -c home create-config /home" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to create snapper home config"
        return 1
    fi

    log_cmd "arch-chroot $MNT systemctl enable snapper-timeline.timer snapper-cleanup.timer"
    if ! arch-chroot "$MNT" /bin/bash -c "systemctl enable snapper-timeline.timer snapper-cleanup.timer" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to enable snapper timers"
        return 1
    fi

    log_success "snapper configured"
}

enable_services() {
    log_header "Enabling system services"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "DRY-RUN: would enable NetworkManager, bluetooth, seatd, power-profiles-daemon, sshd, ufw"
        return 0
    fi

    log_cmd "arch-chroot $MNT systemctl enable NetworkManager bluetooth seatd power-profiles-daemon sshd ufw"
    if ! arch-chroot "$MNT" /bin/bash -c "systemctl enable NetworkManager bluetooth seatd power-profiles-daemon sshd ufw" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to enable system services"
        return 1
    fi

    log_success "Services enabled"
}

################################################################################
# MAIN FLOW
################################################################################

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] COMMAND

Commands:
  prepare       Run preflight checks only
  install       Full automated installation
  diagnose      Run diagnostics on current system

Options:
  --dry-run     Simulate without making changes
  --yes         Skip all confirmations
  -v, --verbose Verbose output
  -h, --help    Show this help

Example:
  sudo $0 --dry-run install
  sudo $0 --yes install
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --yes)
                ASSUME_YES=1
                shift
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            prepare|install|diagnose)
                COMMAND="$1"
                shift
                break
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    if [[ -z "${COMMAND:-}" ]]; then
        log_error "No command specified"
        usage
        exit 1
    fi
}

run_install() {
    log_header "Starting Arch Linux installation"

    require_root

    log_config

    cleanup_target
    trap cleanup_target EXIT

    preflight_checks || return 1

    if [[ $ASSUME_YES -eq 0 && $DRY_RUN -eq 0 ]]; then
        if ! confirm "Proceed with installation on $DISK? This will erase all data."; then
            log_info "Installation cancelled"
            return 1
        fi
    fi

    partition_disk || return 1
    setup_luks_lvm || return 1
    format_filesystems || return 1
    generate_fstab || return 1
    install_base_system || return 1

    # System configuration
    configure_locale || return 1
    configure_hostname || return 1
    configure_mkinitcpio || return 1
    install_bootloader || return 1

    # Users and security
    setup_users || return 1
    setup_pam_faillock || return 1

    # Advanced features
    setup_zram || return 1
    setup_snapper || return 1
    enable_services || return 1

    cleanup_target
    log_success "Installation completed!"
    log_info "Run 'sudo $0 diagnose' after first boot to validate system"
}

run_diagnose() {
    log_header "Running system diagnostics"

    require_root

    local passed=0 failed=0

    # Check UEFI
    if [[ -d /sys/firmware/efi ]]; then
        log_success "UEFI boot detected"
        ((passed++))
    else
        log_warn "UEFI not detected"
        ((failed++))
    fi

    # Check root mount
    if mount | grep -q " / "; then
        log_success "Root filesystem mounted"
        ((passed++))
    else
        log_warn "Root filesystem not found in mount list"
        ((failed++))
    fi

    # Check bootloader
    if [[ -d /boot/loader/entries ]]; then
        log_success "systemd-boot installed"
        ((passed++))
    else
        log_warn "systemd-boot entries not found"
        ((failed++))
    fi

    # Check LUKS
    if blkid -t TYPE="crypto_LUKS" &>/dev/null; then
        log_success "LUKS encryption detected"
        ((passed++))
    else
        log_warn "No LUKS devices found"
        ((failed++))
    fi

    # Check btrfs
    if mount | grep -q "type btrfs"; then
        log_success "btrfs filesystem active"
        ((passed++))
    else
        log_warn "btrfs filesystem not found"
        ((failed++))
    fi

    # Check key packages
    for pkg in base linux sudo systemd; do
        if pacman -Q "$pkg" &>/dev/null; then
            log_success "Package $pkg installed"
            ((passed++))
        else
            log_warn "Package $pkg not found"
            ((failed++))
        fi
    done

    log_header "Diagnostic summary"
    log_info "Passed: $passed, Failed: $failed"

    if [[ $failed -gt 0 ]]; then
        return 1
    fi
}

main() {
    parse_args "$@"

    {
        echo "================================================================================"
        echo "Arch Linux Installer - $(date)"
        echo "================================================================================"
        echo "Log file: $LOG_FILE"
        echo "Script mode: $([ $DRY_RUN -eq 1 ] && echo 'DRY-RUN' || echo 'LIVE')"
        echo "================================================================================"
    } | tee -a "$LOG_FILE"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_warn "Running in DRY-RUN mode (no changes will be made)"
    fi

    case "$COMMAND" in
        prepare)
            require_root
            log_config
            preflight_checks
            ;;
        install)
            run_install
            ;;
        diagnose)
            run_diagnose
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            usage
            exit 1
            ;;
    esac
}

main "$@"