# Arch Linux Installation Scripts

Скрипты для установки и диагностики Arch Linux с Hyprland на ASUS TUF Gaming F15 (RTX 3050).

## Скрипты

### install-arch.sh
Автоматизированная установка Arch Linux с:
- BTRFS субтомами (`@`, `@home`, `@var`, `@tmp`, `@log`, `@snapshots`)
- LUKS2 шифрованием (опционально, `--no-luks` для отключения)
- systemd-boot загрузчиком
- Hyprland + NVIDIA драйверами

**Использование:**
```bash
# Полная установка
sudo ./install-arch.sh

# Без шифрования
sudo ./install-arch.sh --no-luks

# С указанием диска
sudo ./install-arch.sh --disk /dev/sda --hostname myhost
```

**Переменные окружения:**
- `DISK` — целевой диск (по умолчанию `/dev/nvme0n1`)
- `HOSTNAME` — имя хоста (по умолчанию `hyprarch`)
- `USERNAME` — пользователь (по умолчанию `kyomu`)
- `TIMEZONE` — часовой пояс (по умолчанию `Europe/Moscow`)
- `ENABLE_LUKS`, `ENABLE_MULTILIB`, `ENABLE_UFW`, `ENABLE_SNAPPER` — флаги функций

---

### check.sh
Диагностический скрипт для проверки готовой системы:
- UEFI, systemd-boot, initramfs
- Btrfs субтомы, LUKS, LVM
- Службы (NetworkManager, Bluetooth, UFW, Snapper)
- PipeWire, NVIDIA, Hyprland
- Журналы ошибок, обновления пакетов

**Использование:**
```bash
./check.sh
# Лог сохраняется в ./check.log
```

## Требования

- Загрузка в UEFI режиме
- Интернет соединение
- Arch Linux ISO с live-средой
- Доступ к целевому диску

## Лицензия

MIT