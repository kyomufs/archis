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

    # === Ядро и модули ===

    # === Файловые системы и шифрование ===

    # === Загрузчик ===

    # === Сеть ===

    # === Bluetooth ===

    # === Аудио ===

    # === Питание ===

    # === Безопасность ===

    # === Шрифты ===

    # === Hyprland Core ===

    # === Wayland инфраструктура ===

    # === Терминал и редакторы ===

    # === Файловый менеджер ===

    # === Темизация ===

    # === Приложения ===

    # === SSH и ключи ===
    
    # === GPU ===
    
    # === CPU ===

    # === Intel iGPU ===

    # === Диагностика ===

15. Timezone
    1. timezone: Europe/Moscow

16. Automatic time sync (NTP)
    NTP: enabled

17. Setting up pam_faillock, wrong attempts 5, ban time: 10 seconds