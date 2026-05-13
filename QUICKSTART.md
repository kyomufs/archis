# Quick Start Guide

## New Unified Script

The Arch Linux installer is now available as a single modular script: **`archinstall.sh`**

### Basic Usage

```bash
# Make it executable (on Linux)
chmod +x archinstall.sh

# Test mode: see what would happen without making changes
sudo ./archinstall.sh --dry-run install

# Full installation: automated with confirmations
sudo ./archinstall.sh install

# Full installation: completely automated (no prompts)
sudo ./archinstall.sh --yes install

# After reboot: validate the system
sudo ./archinstall.sh diagnose

# Get help
./archinstall.sh --help
```

### Custom Configuration

Edit the variables at the top of `archinstall.sh`:

```bash
DISK="/dev/nvme0n1"          # Target disk
HOSTNAME="hyprarch"           # Computer name
USER_NAME="kyomu"             # Regular user
KEYMAP="us"                   # Keyboard layout
LOCALE="en_US.UTF-8"          # System language
TIMEZONE="Europe/Moscow"      # Your timezone
```

### Installation Steps (Automated)

1. **Partitioning**: GPT + EFI + LVM partition layout
2. **Encryption**: LUKS on LVM with passphrase
3. **Filesystems**: Btrfs with subvolumes (@, @home) and zstd compression
4. **Base System**: Core packages + Hyprland desktop + utilities
5. **Bootloader**: Systemd-boot with secure kernel parameters
6. **Locale**: Timezone, keyboard layout, language
7. **Users**: Root + regular user with sudo access
8. **Security**: PAM faillock (5 failed attempts = 10s lockout)
9. **Services**: NetworkManager, SSH, UFW firewall enabled
10. **Advanced**: Zram swap, snapper snapshots for btrfs

### What's Included

✓ Full disk encryption (LUKS on LVM)
✓ Btrfs snapshots with snapper
✓ Hyprland desktop environment
✓ NVIDIA + Intel GPU drivers
✓ Pipewire audio
✓ Zen browser + development tools
✓ Firewall (UFW) enabled by default
✓ System hardening (pam_faillock)

### Safety Features

- `--dry-run`: Simulate without making changes
- `--yes`: Skip all prompts but show what's happening
- Preflight checks before installation starts
- `diagnose` command to validate post-installation

### Troubleshooting

If something goes wrong:

1. Check the log: `tail -f logs/install-*.log`
2. Verify you're booted in UEFI mode: `ls /sys/firmware/efi`
3. Confirm the target disk: `lsblk`
4. Run preflight checks: `sudo ./archinstall.sh prepare`

### After Installation

On first boot:

```bash
sudo ./archinstall.sh diagnose    # Validate system
sudo pacman -Syu                   # Update all packages
```

---

For detailed configuration, see `arhcinst.md`.
