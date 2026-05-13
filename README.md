Arch Linux Automated Installer (Single Script)

A unified, modular bash script for fully automated Arch Linux installation with LVM on LUKS encryption, Btrfs, systemd-boot, and Hyprland desktop.

Quick Start

```bash
sudo ./archinstall.sh --dry-run install    # Test mode
sudo ./archinstall.sh --yes install        # Full installation
sudo ./archinstall.sh diagnose             # Validate after reboot
```

Features

✓ Automated full installation (partitioning, encryption, formatting)
✓ LVM on LUKS encryption with secure boot parameters
✓ Btrfs with subvolumes and zstd compression
✓ Snapper snapshots for rollback capability
✓ Hyprland Wayland desktop environment
✓ NVIDIA + Intel GPU support
✓ Zram swap for efficiency
✓ PAM faillock security (5 attempts, 10s lockout)
✓ Systemd-boot bootloader
✓ Complete package ecosystem (500+ packages)
✓ Dry-run mode for safety testing

Installation

1. Boot Arch ISO in UEFI mode
2. Clone this repo or download `archinstall.sh`
3. Edit variables if needed (disk, hostname, user, locale)
4. Run: `sudo ./archinstall.sh --yes install`
5. After reboot: `sudo ./archinstall.sh diagnose`

Configuration

Edit the top of `archinstall.sh` to customize:
- `DISK`: Target disk device
- `HOSTNAME`: Computer name
- `USER_NAME`: Regular user account
- `LOCALE`, `TIMEZONE`, `KEYMAP`: System localization
- `ROOT_PASS`, `USER_PASS`: Account passwords
- `ZRAM_ALGORITHM`: Swap compression (default: zstd)
- `FAILLOCK_*`: Security lockout settings

Files

- `archinstall.sh`: Main unified installation script (single file, modular functions)
- `arhcinst.md`: Detailed configuration template
- `QUICKSTART.md`: Quick reference guide
- `INFO.md`: Russian language information
- `logs/`: Installation logs (auto-generated)

Options

```
--dry-run    Simulate without making changes
--yes        Skip all prompts (proceed with caution)
-v, --verbose Verbose output
-h, --help    Show help message
```

Commands

```
prepare      Run preflight checks only
install      Full automated installation
diagnose     Check system health (post-install)
```

Safety

- Always test with `--dry-run` first
- Verify target disk with `lsblk`
- Installation requires root and UEFI boot
- All data on target disk will be erased

For detailed information, see `QUICKSTART.md` or `arhcinst.md`.

