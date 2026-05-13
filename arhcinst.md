# Arch Linux Installation Template (archinstall.sh)

All stages are automated in a single modular script. Usage:
```bash
chmod +x archinstall.sh
sudo ./archinstall.sh --dry-run install     # Test run
sudo ./archinstall.sh --yes install          # Full install (no prompts)
sudo ./archinstall.sh diagnose               # Check system after reboot
```

---

## Installation Stages

1. Set language: 
    1. English

2. Locales:
    1. Keyboard Layout: us
    2. Locale Language: en_US.UTF-8
    3. Locale encoding: UTF-8

3. Mirrors and Repositories
    1. Select regions: Russian
    2. Add custom servers: enter url
    3. Optional repositories: multilib, multilib-testing, core-testing, extra-testing
    4. Add custom repository: enter repository name

4. Disk Configuraation
    1. Partitioning:
        1. dev/nvme0n1
    2. LVM
        1. File system: btrfs
        2. Use compression: yes
    3. Disk encryption
        1. Encryption type: LVM on LUKS
        2. Encryption password: user123
        3. Iteration time: 2000ms
        4. Partitions: create
    4. BTRFS snapshots:
        1. Snapper
        
5. Swap on zram
    1. Algoritm: zstd
6. Bootloader
    1. Bootloader: Systemd-boot
    2. Unified kernel images: enable
7. Kernels
    1. kernel: linux
8. Hostname
    1. hyprarch
9. Authentication
    1. Root password: root123
    2. User account:
        1. username: kyomu
        2. password: user123
        3. Add kyomu to superuser(sudo)

10. Profile
    1. Hyprland
    2. agent: polkit
    3. greater: no
11. Applications
    1. Bluetooth: bluez bluez-utils blueman
    2. Audio: pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber pavucontrol playerctl
    3. Power managment: power-profiles-daemon
    4. Firewwall: ufw
    5. Fonts: noto-fonts

12. Network Configuration
    1. Network manager: default backend

13. Pacman 
    1. Color: true

14. Additional packages
    # === База системы ===
    base
    base-devel
    linux-firmware
    sudo
    git
    man-db
    man-pages

    # === Ядро и модули ===
    linux
    linux-headers
    dkms

    # === Файловые системы и шифрование ===
    btrfs-progs
    lvm2
    cryptsetup
    snapper          # для BTRFS snapshots
    snap-pac

    # === Загрузчик ===
    efibootmgr       # для systemd-boot в UEFI

    # === Сеть ===
    networkmanager
    iwd

    # === Bluetooth ===
    bluez
    bluez-utils
    blueman

    # === Аудио ===
    pipewire
    pipewire-pulse
    pipewire-alsa
    pipewire-jack
    wireplumber
    pavucontrol
    playerctl
    sof-firmware

    # === Питание ===
    power-profiles-daemon
    brightnessctl   # яркость экрана ноутбука

    # === Безопасность ===
    ufw

    # === Шрифты ===
    noto-fonts

    # === Hyprland Core ===
    hyprland
    hyprlock
    hypridle
    hyprpaper
    hyprpicker
    hyprsunset
    hyprpolkitagent  # исправлено: hyprpolkit → hyprpolkitagent
    polkit
    seatd            # fallback для запуска Hyprland

    # === Wayland инфраструктура ===
    xorg-xwayland
    qt5-wayland
    qt6-wayland
    wl-clipboard
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    xdg-utils          # исправлено: xgd-utils → xdg-utils
    egl-wayland

    # === Терминал и редакторы ===
    kitty
    nvim
    nano

    # === Файловый менеджер ===
    dolphin
    7zip
    tar
    gzip
    pigz

    # === Темизация ===
    nwg-look
    qt5ct
    qt6ct

    # === Скриншоты ===
    grim
    slurp

    # === Приложения ===
    zen-browser
    gwenview
    btop

    # === SSH и ключи ===
    openssh
    gnome-keyring

    # === NVIDIA ===
    nvidia-open-dkms  # или nvidia-dkms если open глючит
    nvidia-utils
    nvidia-settings
    lib32-nvidia-utils
    libva-nvidia-driver
    nvidia-prime
    switcheroo-control
    acpi_call

    # === Intel iGPU ===
    mesa
    vulkan-intel
    intel-media-driver
    lib32-mesa
    lib32-vulkan-intel
    intel-ucode

    # === Диагностика ===
    mesa-utils
    vulkan-tools

    # === GPU переключение ===
    envycontrol


15. Timezone
    1. timezone: Europe/Moscow

16. Automatic time sync (NTP)
    NTP: enabled

17. Setting up pam_faillock, wrong attempts 5, ban time: 10 seconds

---

## Script Configuration

All stages in `archinstall.sh` can be customized by editing the variables at the top of the file:

- `DISK`: Target disk (default: /dev/nvme0n1)
- `KEYMAP`: Keyboard layout (default: us)
- `LOCALE`: System locale (default: en_US.UTF-8)
- `TIMEZONE`: Timezone (default: Europe/Moscow)
- `HOSTNAME`: Computer name (default: hyprarch)
- `USER_NAME`: Regular user (default: kyomu)
- `ZRAM_ALGORITHM`: Compression for swap (default: zstd)
- `FAILLOCK_DENY`: Max login attempts before lockout (default: 5)
- `FAILLOCK_UNLOCK_TIME`: Lockout duration in seconds (default: 10)

## Script Features

✓ Automated full installation with LVM on LUKS encryption
✓ Btrfs with subvolumes (@, @home) and compression (zstd)
✓ Systemd-boot bootloader with secure kernel parameters
✓ Snapper integration for automated btrfs snapshots
✓ Zram swap for efficiency
✓ PAM faillock for security
✓ Desktop environment (Hyprland) pre-configured
✓ NVIDIA + Intel GPU support
✓ Dry-run and confirmation modes for safety

## Workflow

1. Edit variables in archinstall.sh if needed
2. Boot Arch ISO in UEFI mode
3. Run: `sudo archinstall.sh --dry-run install` (see what would happen)
4. Run: `sudo archinstall.sh --yes install` (full installation)
5. After reboot, verify: `sudo archinstall.sh diagnose`