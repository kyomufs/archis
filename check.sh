#!/usr/bin/env bash
# Скрипт диагностики Arch Linux
# Сохраняет результаты в файл check.log в текущей директории
set -uo pipefail

# Цвета для консоли (не пишем в лог)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Файл лога
LOG_FILE="./check.log"

# Счётчики для итогов
PASSED=0
FAILED=0
WARNINGS=0

# Очистка старого лога
> "$LOG_FILE"

# Функция для дублирования вывода в консоль и лог-файл
log() {
    local level="$1"   # INFO, SUCCESS, WARNING, ERROR, HEADER
    local msg="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Запись в лог-файл без цветов
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    
    # Вывод в консоль с цветами
    case "$level" in
        INFO)    echo -e "${BLUE}[i]${NC} $msg" ;;
        SUCCESS) echo -e "${GREEN}[✓]${NC} $msg" ;;
        WARNING) echo -e "${YELLOW}[!]${NC} $msg" ;;
        ERROR)   echo -e "${RED}[x]${NC} $msg" ;;
        HEADER)  echo -e "\n${BLUE}==>${NC} ${GREEN}$msg${NC}" ;;
        *)       echo "$msg" ;;
    esac
}

# Функция выполнения команды с сохранением вывода в лог
run_cmd() {
    local desc="$1"
    local cmd="$2"
    log INFO "Проверка: $desc"
    echo ">>> $cmd" >> "$LOG_FILE"
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        log SUCCESS "  OK: $desc"
        PASSED=$((PASSED + 1))
        return 0
    else
        log ERROR "  FAIL: $desc"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# Функция проверки условия
check_condition() {
    local desc="$1"
    local condition="$2"
    log INFO "Проверка: $desc"
    echo ">>> $condition" >> "$LOG_FILE"
    if eval "$condition" >> "$LOG_FILE" 2>&1; then
        log SUCCESS "  OK: $desc"
        PASSED=$((PASSED + 1))
        return 0
    else
        log ERROR "  FAIL: $desc"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# Функция проверки с предупреждением (не увеличивает счётчик FAILED)
check_warn() {
    local desc="$1"
    local condition="$2"
    log INFO "Проверка: $desc"
    echo ">>> $condition" >> "$LOG_FILE"
    if eval "$condition" >> "$LOG_FILE" 2>&1; then
        log SUCCESS "  OK: $desc"
        PASSED=$((PASSED + 1))
        return 0
    else
        log WARNING "  WARN: $desc"
        WARNINGS=$((WARNINGS + 1))
        return 1
    fi
}

# Вывод вывода команды без оценки (просто лог)
log_cmd_output() {
    local desc="$1"
    local cmd="$2"
    log INFO "$desc"
    echo ">>> $cmd" >> "$LOG_FILE"
    eval "$cmd" >> "$LOG_FILE" 2>&1
    log INFO "  Команда выполнена (вывод в лог)"
}

################################################################################
# НАЧАЛО ДИАГНОСТИКИ
################################################################################

log HEADER "===== ДИАГНОСТИКА СИСТЕМЫ ARCH LINUX ====="
log INFO "Лог-файл: $LOG_FILE"
log INFO "Дата: $(date)"

# 1. Проверка загрузки и UEFI
log HEADER "1. ЗАГРУЗКА И UEFI"
check_condition "Режим UEFI" "[[ -d /sys/firmware/efi ]]"
run_cmd "Параметры ядра" "cat /proc/cmdline"
check_condition "systemd-boot установлен" "[[ -d /boot/loader/entries ]]"
run_cmd "Статус bootctl" "bootctl status"
run_cmd "Содержимое /boot/loader/entries" "ls -l /boot/loader/entries"

# 2. Файловые системы, LUKS, LVM
log HEADER "2. ФАЙЛОВЫЕ СИСТЕМЫ, LUKS, LVM"
run_cmd "lsblk -f" "lsblk -f"
check_condition "LUKS устройство найдено" "blkid -t TYPE='crypto_LUKS' &>/dev/null"
run_cmd "Статус cryptlvm" "sudo cryptsetup status cryptlvm 2>/dev/null || echo 'Не найдено'"
run_cmd "LVM: pvs/vgs/lvs" "sudo pvs && sudo vgs && sudo lvs"
run_cmd "Смонтированные btrfs" "mount | grep btrfs"
check_condition "Подтом @ примонтирован в /" "mount | grep -q 'on / .*subvol=/@'"
check_condition "Подтом @home примонтирован в /home" "mount | grep -q '/home .*subvol=/@home'"
check_condition "Подтом @snapshots примонтирован в /.snapshots" "mount | grep -q '/.snapshots .*subvol=/@snapshots'"
run_cmd "Содержимое /etc/fstab" "cat /etc/fstab"
check_condition "В /boot в fstab есть fmask,dmask" "grep -q 'fmask=0137,dmask=0027' /etc/fstab"
check_condition "Права /boot (750/640)" "[[ $(stat -c %a /boot) == 750 ]] && ls -l /boot/loader/random-seed | grep -q '^-rw-r-----'"

# 3. initramfs и модули
log HEADER "3. INITRAMFS И МОДУЛИ ЯДРА"
check_condition "initramfs содержит encrypt и lvm2" "lsinitcpio /boot/initramfs-linux.img | grep -qE 'encrypt|lvm2'"
run_cmd "Загруженные модули (nvidia, btrfs, lvm, crypt)" "lsmod | grep -E 'nvidia|btrfs|lvm|crypt'"
check_warn "Нет предупреждений о qat_6xxx" "! sudo dmesg | grep -qi 'qat.*firmware'"

# 4. Сеть и службы
log HEADER "4. СЕТЬ И СЛУЖБЫ"
check_condition "NetworkManager активен" "systemctl is-active NetworkManager &>/dev/null"
check_condition "Bluetooth активен" "systemctl is-active bluetooth &>/dev/null"
check_condition "seatd активен" "systemctl is-active seatd &>/dev/null"
check_condition "power-profiles-daemon активен" "systemctl is-active power-profiles-daemon &>/dev/null"
check_condition "sshd активен" "systemctl is-active sshd &>/dev/null"
check_condition "ufw активен" "systemctl is-active ufw &>/dev/null"
run_cmd "Статус UFW verbose" "sudo ufw status verbose"
check_condition "snapper-timeline.timer активен" "systemctl is-active snapper-timeline.timer &>/dev/null"
check_condition "snapper-cleanup.timer активен" "systemctl is-active snapper-cleanup.timer &>/dev/null"

# 5. Аудио и PipeWire
log HEADER "5. АУДИО И PIPEWIRE"
check_condition "pipewire активен (user)" "systemctl --user is-active pipewire &>/dev/null"
check_condition "pipewire-pulse активен" "systemctl --user is-active pipewire-pulse &>/dev/null"
check_condition "wireplumber активен" "systemctl --user is-active wireplumber &>/dev/null"
run_cmd "Аудиоустройства (pactl)" "pactl info && pactl list short sinks"

# 6. Графика (NVIDIA + Intel)
log HEADER "6. ГРАФИКА (NVIDIA + INTEL)"
check_condition "Модуль nvidia загружен" "lsmod | grep -q nvidia"
run_cmd "Параметр nvidia-drm.modeset" "cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || echo 'не найден'"
run_cmd "OpenGL рендерер (glxinfo)" "glxinfo 2>/dev/null | grep 'OpenGL renderer' || echo 'glxinfo не установлен'"
check_condition "Switcheroo-control активен" "systemctl is-active switcheroo-control &>/dev/null || echo 'сервис не активен'"
run_cmd "prime-run проверка" "prime-run glxinfo 2>/dev/null | grep 'OpenGL renderer' || echo 'prime-run не работает'"

# 7. Hyprland и Wayland
log HEADER "7. HYPRLAND И WAYLAND"
check_condition "XDG_SESSION_TYPE=wayland" "[[ $XDG_SESSION_TYPE == 'wayland' ]]"
check_condition "WAYLAND_DISPLAY установлен" "[[ -n ${WAYLAND_DISPLAY:-} ]]"
run_cmd "Версия hyprctl" "hyprctl version 2>/dev/null || echo 'hyprland не запущен'"
check_warn "Hyprland может быть запущен" "pgrep -x Hyprland &>/dev/null"

# 8. Btrfs и снапшоты
log HEADER "8. BTRFS И СНАПШОТЫ"
run_cmd "Список btrfs подтомов" "sudo btrfs subvolume list /"
run_cmd "Конфигурации snapper" "sudo snapper list-configs"
run_cmd "Снэпшоты root" "sudo snapper -c root list 2>/dev/null || echo 'нет снэпшотов'"
check_condition "Снэпшот от установки существует" "sudo snapper -c root list 2>/dev/null | grep -q 'post' || echo 'снэпшоты не созданы'"

# 9. Память и zram
log HEADER "9. ПАМЯТЬ И ZRAM"
run_cmd "zramctl" "zramctl"
run_cmd "Swap области" "swapon --show"
check_condition "zram используется как swap" "swapon --show | grep -q zram"

# 10. Журналы и ошибки (за исключением ACPI, если пользователь не хочет их видеть)
log HEADER "10. ЖУРНАЛЫ И ОШИБКИ"
log_cmd_output "Ошибки уровня 0-3 (первые 20 строк)" "sudo journalctl -p 3 -b --no-pager | head -20"
log_cmd_output "Ошибки ACPI (все)" "sudo journalctl -b --no-pager | grep -i 'ACPI Error\|ACPI Exception\|ACPI Bug' || echo 'Нет ACPI ошибок'"
check_warn "Нет критических ошибок помимо ACPI" "! sudo journalctl -p 3 -b --no-pager | grep -v 'ACPI' | grep -q '.'"

# 11. Целостность пакетов и обновления
log HEADER "11. ПАКЕТЫ И ОБНОВЛЕНИЯ"
run_cmd "Проверка конфликтов пакетов" "sudo pacman -Qk 2>&1 | head -20"
run_cmd "Установленные версии ключевых пакетов" "pacman -Q base linux linux-firmware nvidia-open-dkms hyprland terminus-font 2>/dev/null || echo 'некоторые пакеты не найдены'"
run_cmd "Доступные обновления (dry-run)" "sudo pacman -Syu --dry-run 2>&1 | head -20"

# 12. Время загрузки и таймеры
log HEADER "12. ВРЕМЯ ЗАГРУЗКИ И ТАЙМЕРЫ"
run_cmd "systemd-analyze" "systemd-analyze"
run_cmd "systemd-analyze blame (первые 10)" "systemd-analyze blame | head -10"
run_cmd "Активные таймеры" "systemctl list-timers --all --no-pager | head -20"

################################################################################
# ИТОГИ
################################################################################

log HEADER "===== ИТОГИ ДИАГНОСТИКИ ====="
log INFO "Пройдено проверок: $PASSED"
log INFO "Не пройдено: $FAILED"
if [[ $WARNINGS -gt 0 ]]; then
    log WARNING "Предупреждений: $WARNINGS"
fi

if [[ $FAILED -eq 0 ]]; then
    log SUCCESS "Все критические проверки успешны!"
else
    log ERROR "Обнаружено $FAILED проблем. Проверьте лог-файл $LOG_FILE"
fi

echo ""
log INFO "Полный лог сохранён в $LOG_FILE"
echo ""

exit $FAILED