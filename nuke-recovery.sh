#!/bin/bash
# nuke-recovery.sh — Restore a backed-up EFI partition
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

msg()  { echo -e "${GREEN}[*]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

if [ $# -lt 1 ]; then
    echo "Usage: $0 <backup-dir> [efi-partition]"
    echo ""
    echo "Examples:"
    echo "  $0 /root/efi-backup-20260320180000"
    echo "  $0 /root/efi-backup-20260320180000 /dev/sda1"
    echo ""
    # List available backups
    if ls -d /root/efi-backup-* &>/dev/null; then
        info "Available backups:"
        ls -d /root/efi-backup-* | while read -r d; do
            echo "  $d ($(du -sh "$d" 2>/dev/null | awk '{print $1}'))"
        done
    else
        err "No EFI backups found in /root/"
    fi
    exit 1
fi

BACKUP_DIR="$1"
if [ ! -d "$BACKUP_DIR" ]; then
    err "Backup directory not found: $BACKUP_DIR"
    exit 1
fi

# Find or use provided EFI partition
EFI_PART="${2:-}"
if [ -z "$EFI_PART" ]; then
    info "Scanning for EFI partitions..."
    mapfile -t efi_parts < <(lsblk -lpno NAME,PARTTYPE | grep -i "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" | awk '{print $1}')
    if [ ${#efi_parts[@]} -eq 0 ]; then
        err "No EFI partition found. Specify one manually: $0 $BACKUP_DIR /dev/sdXN"
        exit 1
    elif [ ${#efi_parts[@]} -eq 1 ]; then
        EFI_PART="${efi_parts[0]}"
    else
        echo "Multiple EFI partitions found:"
        for i in "${!efi_parts[@]}"; do
            echo "  $((i+1))) ${efi_parts[$i]}"
        done
        read -rp "Pick [1-${#efi_parts[@]}]: " pick
        EFI_PART="${efi_parts[$((pick-1))]}"
    fi
fi

msg "Restoring EFI backup to $EFI_PART"
info "Backup: $BACKUP_DIR"
info "Target: $EFI_PART"
read -rp "Proceed? [y/n]: " yn
[ "$yn" = "y" ] || exit 0

TMP_MOUNT="/tmp/efi-restore-mount"
mkdir -p "$TMP_MOUNT"
mount "$EFI_PART" "$TMP_MOUNT"
cp -a "$BACKUP_DIR"/. "$TMP_MOUNT/"
umount "$TMP_MOUNT"
rmdir "$TMP_MOUNT"

msg "EFI partition restored from $BACKUP_DIR"
