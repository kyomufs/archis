# Arch Linux Installation Script

Автоматический скрипт установки Arch Linux для ноутбука ASUS TUF Gaming F15 (RTX 3050) с Hyprland.

## Особенности

- **LUKS2 + BTRFS** с сжатием zstd
- **Systemd-boot** с UKI (Unified Kernel Images)
- **ZRAM swap** вместо swap partition
- **NVIDIA Optimus** готовая конфигурация
- **Hyprland** с базовыми keybinding'ами
- **Snapper** для снимков BTRFS
- **pam_faillock** для защиты от bruteforce
- **yay** AUR helper

## BTRFS Subvolumes

- `@` - корневой
- `@home` - домашний каталог
- `@var` - для логов и кэшей
- `@tmp` - временные файлы
- `@log` - системные логи
- `@snapshots` - снимки snapper

## Использование

```bash
# Автоматический режим (все функции включены)
sudo ./install-arch.sh

# С флагами для отключения функций
sudo ./install-arch.sh --no-luks           # Без шифрования
sudo ./install-arch.sh --no-ufw           # Без firewall
sudo ./install-arch.sh --no-snapper       # Без снимков
sudo ./install-arch.sh --no-multilib      # Без multilib

# Комбинирование флагов
sudo ./install-arch.sh --no-luks --no-ufw

# Переопределение параметров
sudo ./install-arch.sh --disk /dev/sda --hostname myarch --username admin
```

## Environment Variables

```bash
export USERNAME="youruser"
export HOSTNAME="arch"
export ROOT_PASSWORD="rootpass"
export USER_PASSWORD="userpass"
export LUKS_PASSWORD="lukspass"
```

## NVIDIA Optimus (RTX 3050)

Скрипт настраивает переменные среды для Hyprland:
```
LIBVA_DRIVER_NAME=nvidia
__GLX_VENDOR_LIBRARY_NAME=nvidia
GBM_BACKEND=nvidia-drm
AQ_DRM_DEVICES=/dev/dri/card1:/dev/dri/card0
nvidia-drm.modeset=1
```

## Логирование

Все операции логируются в `/tmp/arch-install-*.log`

## После установки

1. После перезагрузки войдите в Hyprland
2. Установите темы: `yay -S catppuccin-mocha-gtk-theme`
3. Настройте обои: скопируйте в `~/Изображения/`
4. Дополнительные пакеты: `yay -S hyprpicker nwg-bar`

## Требования

- UEFI boot
- Интернет соединение
- Arch ISO (2024+)