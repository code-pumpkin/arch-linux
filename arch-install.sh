#!/bin/bash
# Arch Linux Interactive Installer
# Supports: Plain / LVM / LUKS+LVM partitioning, dual-boot, systemd-boot
# WM options: i3 (X11), Sway (Wayland), Hyprland (Wayland), or none

set -euo pipefail

# Resolve the directory where this script lives (for bundled configs)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Global State ---
DISK=""
PART_MODE=""       # plain | lvm | luks
EFI_PART=""
EFI_REUSE=false
ROOT_PART=""
SWAP_PART=""
LUKS_PART=""
LUKS_NAME="cryptlvm"
VG_NAME="vg0"
SWAP_SIZE=""
TIMEZONE=""
LOCALE=""
KEYMAP="us"
KB_LAYOUT="us"
KB_VARIANT=""
HOSTNAME_VAL=""
CPU_UCODE=""
REUSE_EXISTING=false
WM_CHOICE=""       # i3 | user_custom | sway | hyprland | kde | none
AUR_HELPER=""      # yay | paru | none
BROWSER_PKG=""     # firefox | librewolf-bin | chromium | brave-bin | ""
EGPU_SETUP=""      # yes | ""

HOME_PART=""
EXTRA_LV_NAMES=()   # e.g., (data media)
EXTRA_LV_SIZES=()   # e.g., (10G 5G)
EXTRA_LV_MOUNTS=()  # e.g., (/mnt/data /mnt/media)

# --- Helpers ---
msg()  { echo -e "${GREEN}[*]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
header() { echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"; }

confirm() {
    local prompt="${1:-Continue?}"
    while true; do
        read -rp "$(echo -e "${YELLOW}${prompt} [y/n]: ${NC}")" yn
        case "$yn" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

# Classify a partition by its filesystem type
# Returns: efi, swap, linux, luks, windows, unknown
classify_partition() {
    local part="$1"
    local fstype parttype
    fstype=$(lsblk -no FSTYPE "$part" 2>/dev/null | head -1)
    parttype=$(lsblk -no PARTTYPE "$part" 2>/dev/null | head -1)

    # EFI System Partition (GPT type GUID)
    if echo "$parttype" | grep -qi "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"; then
        echo "efi"; return
    fi

    case "$fstype" in
        vfat|fat32)       echo "efi" ;;
        swap)             echo "swap" ;;
        ext2|ext3|ext4|btrfs|xfs|f2fs|LVM2_member) echo "linux" ;;
        crypto_LUKS)      echo "luks" ;;
        ntfs|ntfs-3g|exfat|fuseblk) echo "windows" ;;
        "")               echo "unknown" ;;
        *)                echo "unknown" ;;
    esac
}

# Get free (unpartitioned) space on a disk in GiB
get_free_space_gib() {
    local disk="$1"
    # sgdisk -F returns first free sector, -E returns last free sector
    local first_free last_free sector_size free_bytes
    first_free=$(sgdisk -F "$disk" 2>/dev/null) || { echo "0"; return; }
    last_free=$(sgdisk -E "$disk" 2>/dev/null) || { echo "0"; return; }
    sector_size=$(blockdev --getss "$disk" 2>/dev/null || echo 512)

    if [ -z "$first_free" ] || [ -z "$last_free" ] || [ "$first_free" -ge "$last_free" ] 2>/dev/null; then
        echo "0"; return
    fi

    free_bytes=$(( (last_free - first_free + 1) * sector_size ))
    echo $(( free_bytes / 1024 / 1024 / 1024 ))
}

cleanup() {
    warn "Cleaning up after error..."
    umount -R /mnt 2>/dev/null || true
    if [ "$PART_MODE" = "luks" ] && [ -e "/dev/mapper/$LUKS_NAME" ]; then
        vgchange -an "$VG_NAME" 2>/dev/null || true
        cryptsetup close "$LUKS_NAME" 2>/dev/null || true
    elif [ "$PART_MODE" = "lvm" ]; then
        vgchange -an "$VG_NAME" 2>/dev/null || true
    fi
    swapoff -a 2>/dev/null || true
}
trap cleanup ERR

# ============================================================
# PHASE 1: UEFI Check
# ============================================================
check_uefi() {
    header "UEFI Verification"
    if [ ! -f /sys/firmware/efi/fw_platform_size ]; then
        err "System is NOT booted in UEFI mode (BIOS/CSM detected)."
        err "This installer requires UEFI. Please reboot in UEFI mode."
        exit 1
    fi
    local bits
    bits=$(cat /sys/firmware/efi/fw_platform_size)
    if [ "$bits" = "64" ]; then
        msg "UEFI mode confirmed (64-bit)."
    elif [ "$bits" = "32" ]; then
        warn "32-bit UEFI detected. systemd-boot supports this but it is uncommon."
        confirm "Continue with 32-bit UEFI?" || exit 1
    else
        err "Unexpected UEFI platform size: $bits"
        exit 1
    fi
}

# ============================================================
# PHASE 2: Disk Detection & Partition Analysis
# ============================================================
detect_disks() {
    header "Disk Detection"
    msg "Available block devices:"
    echo ""
    lsblk -dpno NAME,SIZE,MODEL,TYPE | grep -E "disk$" | while read -r line; do
        echo -e "  ${CYAN}${line}${NC}"
    done
    echo ""

    local disks
    mapfile -t disks < <(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}')

    if [ ${#disks[@]} -eq 0 ]; then
        err "No disks found!"
        exit 1
    fi

    if [ ${#disks[@]} -eq 1 ]; then
        DISK="${disks[0]}"
        msg "Only one disk found: $DISK"
        confirm "Use $DISK as the target disk?" || exit 1
    else
        echo "Select target disk:"
        select d in "${disks[@]}"; do
            if [ -n "$d" ]; then
                DISK="$d"
                break
            fi
        done
    fi

    msg "Selected disk: $DISK"
}

analyze_partitions() {
    header "Partition Analysis"
    local part_count
    part_count=$(lsblk -lpno NAME,TYPE "$DISK" | grep -c "part" || true)

    if [ "$part_count" -eq 0 ]; then
        msg "Disk $DISK has no partitions (empty disk)."
        return
    fi

    warn "Disk $DISK has existing partitions:"
    echo ""
    lsblk -lpno NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$DISK" | tail -n +2 | while read -r line; do
        echo -e "  ${YELLOW}${line}${NC}"
    done
    echo ""

    # Detect existing EFI partition via GPT partition type GUID
    local efi_parts
    mapfile -t efi_parts < <(lsblk -lpno NAME,PARTTYPE "$DISK" | grep -i "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" | awk '{print $1}')

    if [ ${#efi_parts[@]} -gt 0 ] && [ -n "${efi_parts[0]}" ]; then
        info "Existing EFI System Partition detected: ${efi_parts[0]}"
        warn "This likely means another OS is installed (dual-boot scenario)."
        if confirm "Reuse existing EFI partition ${efi_parts[0]} for dual-boot?"; then
            EFI_PART="${efi_parts[0]}"
            EFI_REUSE=true
            msg "Will reuse EFI partition: $EFI_PART"
        fi
    fi

    # Check if partitions have data
    lsblk -lpno NAME,FSTYPE "$DISK" | tail -n +2 | while read -r pname pfs; do
        if [ -n "$pfs" ]; then
            warn "Partition $pname has filesystem ($pfs) - may contain data!"
        fi
    done

    echo ""
    warn "Existing partitions detected on this disk."
    confirm "Continue? (Partitions may be modified/destroyed)" || exit 1
}

# ============================================================
# PHASE 3: Partition Mode Selection & Creation
# ============================================================
select_partition_mode() {
    header "Partition Mode Selection"
    echo -e "  ${BOLD}1)${NC} Plain   - Standard partitions (EFI + Swap + Root)"
    echo -e "  ${BOLD}2)${NC} LVM     - Logical Volume Manager (EFI + LVM with Swap + Root)"
    echo -e "  ${BOLD}3)${NC} LUKS    - Encrypted LUKS + LVM (EFI + encrypted container with Swap + Root)"
    echo ""
    while true; do
        read -rp "Select partition mode [1/2/3]: " choice
        case "$choice" in
            1) PART_MODE="plain"; break ;;
            2) PART_MODE="lvm"; break ;;
            3) PART_MODE="luks"; break ;;
            *) echo "Invalid choice." ;;
        esac
    done
    msg "Selected mode: $PART_MODE"
}

get_swap_size() {
    local ram_kb ram_gb suggested
    ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    ram_gb=$(( ram_kb / 1024 / 1024 ))
    suggested=$(( ram_gb < 4 ? 4 : ram_gb ))
    info "System RAM: ~${ram_gb}G. Suggested swap: ${suggested}G"
    read -rp "Swap size in GB [${suggested}]: " SWAP_SIZE
    SWAP_SIZE="${SWAP_SIZE:-$suggested}"
}

handle_existing_disk() {
    header "Disk Preparation"
    local part_count
    part_count=$(lsblk -lpno NAME,TYPE "$DISK" | grep -c "part" || true)

    if [ "$part_count" -eq 0 ]; then
        msg "Disk is empty. Creating fresh GPT partition table..."
        sgdisk --zap-all "$DISK" 2>/dev/null || true
        sgdisk -o "$DISK"
        partprobe "$DISK" 2>/dev/null
        udevadm settle 2>/dev/null || sleep 2
        return 0
    fi

    # --- Classify every partition on the disk ---
    local parts classes
    mapfile -t parts < <(lsblk -lpno NAME,TYPE "$DISK" | awk '$2=="part"{print $1}')
    declare -a classes=()
    local has_linux=false has_luks=false has_reusable=false
    local -a reusable_parts=()

    echo ""
    msg "Partition analysis for $DISK:"
    echo ""
    printf "  ${BOLD}%-20s %-8s %-14s %-10s %-s${NC}\n" "PARTITION" "SIZE" "FSTYPE" "CLASS" "ACTION"
    echo "  ────────────────────────────────────────────────────────────────────"

    for p in "${parts[@]}"; do
        local cls size fstype action_hint
        cls=$(classify_partition "$p")
        size=$(lsblk -no SIZE "$p" 2>/dev/null | head -1 | xargs)
        fstype=$(lsblk -no FSTYPE "$p" 2>/dev/null | head -1)
        fstype="${fstype:-(empty)}"

        case "$cls" in
            efi)     action_hint="keep (boot)" ;;
            swap)    action_hint="reusable"
                     has_reusable=true; reusable_parts+=("$p") ;;
            linux)   action_hint="reusable"
                     has_linux=true; has_reusable=true; reusable_parts+=("$p") ;;
            luks)    action_hint="reusable"
                     has_luks=true; has_reusable=true; reusable_parts+=("$p") ;;
            windows) action_hint="skip (Windows)" ;;
            *)       action_hint="skip (unknown)" ;;
        esac

        classes+=("$cls")
        local color="$NC"
        case "$cls" in
            windows) color="$RED" ;;
            linux|luks|swap) color="$GREEN" ;;
            efi) color="$CYAN" ;;
        esac
        printf "  ${color}%-20s %-8s %-14s %-10s %-s${NC}\n" "$p" "$size" "$fstype" "$cls" "$action_hint"
    done
    echo ""

    # --- Free space check ---
    local free_gib
    free_gib=$(get_free_space_gib "$DISK")
    local has_free=false
    if [ "$free_gib" -gt 1 ] 2>/dev/null; then
        has_free=true
        msg "Free (unpartitioned) space: ~${free_gib} GiB"
    else
        info "No significant free space on disk."
    fi
    echo ""

    # --- Build menu dynamically ---
    local -a menu_labels=() menu_actions=()
    local opt=1

    menu_labels+=("Wipe entire disk and start fresh")
    menu_actions+=("wipe")

    if [ "$has_free" = true ]; then
        menu_labels+=("Use free space (~${free_gib} GiB)")
        menu_actions+=("free")
    fi

    if [ "$has_reusable" = true ]; then
        menu_labels+=("Reuse an existing Linux/LUKS/swap partition")
        menu_actions+=("reuse")
    fi

    menu_labels+=("Shrink an existing partition to make room")
    menu_actions+=("shrink")

    for i in "${!menu_labels[@]}"; do
        echo -e "  ${BOLD}$((i+1)))${NC} ${menu_labels[$i]}"
    done
    echo ""

    local disk_action
    while true; do
        read -rp "Choose action [1-${#menu_labels[@]}]: " disk_action
        if [[ "$disk_action" =~ ^[0-9]+$ ]] && [ "$disk_action" -ge 1 ] && [ "$disk_action" -le "${#menu_labels[@]}" ]; then
            break
        fi
        echo "Invalid choice."
    done

    case "${menu_actions[$((disk_action-1))]}" in
        wipe)
            warn "THIS WILL DESTROY ALL DATA ON $DISK"
            confirm "Are you absolutely sure?" || exit 1
            # Tear down any active LVM/LUKS on this disk before wiping
            swapoff -a 2>/dev/null || true
            umount -R /mnt 2>/dev/null || true
            # Remove VGs if LVM metadata still intact
            for vg in $(vgs --noheadings -o vg_name 2>/dev/null | xargs); do
                vgremove -ff "$vg" 2>/dev/null || true
            done
            # Force-remove any orphaned device-mapper nodes (LVs then LUKS)
            for dm in $(dmsetup ls 2>/dev/null | awk '{print $1}' | grep -v '^control$' | sort -r); do
                dmsetup remove -f "$dm" 2>/dev/null || true
            done
            # Wipe all filesystem signatures from every partition
            for part in $(lsblk -lpno NAME,TYPE "$DISK" | awk '$2=="part"{print $1}'); do
                wipefs -af "$part" 2>/dev/null || true
            done
            # Nuke partition table and create fresh GPT
            sgdisk --zap-all "$DISK"
            wipefs -af "$DISK" 2>/dev/null || true
            sgdisk -o "$DISK"
            partprobe "$DISK" 2>/dev/null
            udevadm settle 2>/dev/null || sleep 2
            msg "Disk wiped."
            ;;
        free)
            msg "Will create partitions in the ${free_gib} GiB of free space."
            ;;
        reuse)
            reuse_existing_partition
            ;;
        shrink)
            shrink_partition
            ;;
    esac
}

reuse_existing_partition() {
    header "Reuse Existing Partition"

    # List only reusable partitions (linux, luks, swap)
    local -a candidates=() cand_classes=()
    local parts_all
    mapfile -t parts_all < <(lsblk -lpno NAME,TYPE "$DISK" | awk '$2=="part"{print $1}')

    for p in "${parts_all[@]}"; do
        local cls
        cls=$(classify_partition "$p")
        case "$cls" in
            linux|luks|swap)
                candidates+=("$p")
                cand_classes+=("$cls")
                ;;
        esac
    done

    if [ ${#candidates[@]} -eq 0 ]; then
        err "No reusable partitions found."
        exit 1
    fi

    echo "Reusable partitions:"
    for i in "${!candidates[@]}"; do
        local size fstype
        size=$(lsblk -no SIZE "${candidates[$i]}" 2>/dev/null | head -1 | xargs)
        fstype=$(lsblk -no FSTYPE "${candidates[$i]}" 2>/dev/null | head -1)
        echo -e "  ${BOLD}$((i+1)))${NC} ${candidates[$i]}  ${size}  ${fstype}  [${cand_classes[$i]}]"
    done
    echo ""

    # --- Pick root partition ---
    local root_choice
    while true; do
        read -rp "Select partition to use as ROOT [1-${#candidates[@]}]: " root_choice
        if [[ "$root_choice" =~ ^[0-9]+$ ]] && [ "$root_choice" -ge 1 ] && [ "$root_choice" -le "${#candidates[@]}" ]; then
            break
        fi
        echo "Invalid choice."
    done

    local picked="${candidates[$((root_choice-1))]}"
    local picked_cls="${cand_classes[$((root_choice-1))]}"

    echo ""
    echo -e "  ${BOLD}1)${NC} Reuse as-is  — Format and install on this partition"
    echo -e "  ${BOLD}2)${NC} Nuke and rebuild — Delete this partition, create fresh layout"
    local reuse_action
    while true; do
        read -rp "Action [1/2]: " reuse_action
        case "$reuse_action" in
            1) break ;;
            2)
                warn "Deleting $picked — all data will be lost."
                confirm "Proceed?" || exit 1
                swapoff "$picked" 2>/dev/null || true
                umount "$picked" 2>/dev/null || true
                # Tear down LUKS/LVM if present
                if [ "$picked_cls" = "luks" ]; then
                    local mapper_name
                    mapper_name=$(lsblk -no NAME "$picked" 2>/dev/null | tail -1)
                    if [ -e "/dev/mapper/$mapper_name" ]; then
                        local vg
                        vg=$(pvs --noheadings -o vg_name "/dev/mapper/$mapper_name" 2>/dev/null | xargs)
                        [ -n "$vg" ] && vgremove -ff "$vg" 2>/dev/null || true
                        cryptsetup close "$mapper_name" 2>/dev/null || true
                    fi
                fi
                wipefs -af "$picked" 2>/dev/null || true
                local partnum
                partnum=$(echo "$picked" | grep -oP '\d+$')
                sgdisk -d "$partnum" "$DISK"
                partprobe "$DISK" 2>/dev/null
                udevadm settle 2>/dev/null || sleep 2
                msg "Deleted $picked. Free space available for new partitions."
                REUSE_EXISTING=false
                return
                ;;
            *) echo "Invalid choice." ;;
        esac
    done

    if [ "$picked_cls" = "luks" ]; then
        warn "This is a LUKS-encrypted partition."
        info "You will need to unlock it. The installer will set up LVM inside."
        PART_MODE="luks"
        LUKS_PART="$picked"
        msg "Opening LUKS container on $LUKS_PART..."
        cryptsetup open "$LUKS_PART" "$LUKS_NAME"

        # Check if VG already exists inside
        if pvs "/dev/mapper/$LUKS_NAME" &>/dev/null; then
            local existing_vg
            existing_vg=$(pvs --noheadings -o vg_name "/dev/mapper/$LUKS_NAME" 2>/dev/null | xargs)
            if [ -n "$existing_vg" ]; then
                VG_NAME="$existing_vg"
                vgchange -ay "$VG_NAME"
                info "Found existing VG: $VG_NAME"
                if lvs "$VG_NAME/root" &>/dev/null; then
                    ROOT_PART="/dev/$VG_NAME/root"
                    msg "Found existing root LV: $ROOT_PART"
                fi
                if lvs "$VG_NAME/swap" &>/dev/null; then
                    SWAP_PART="/dev/$VG_NAME/swap"
                    msg "Found existing swap LV: $SWAP_PART"
                fi
            fi
        fi

        # If no existing root LV, create fresh LVM inside the LUKS container
        if [ -z "$ROOT_PART" ]; then
            get_swap_size
            pvcreate -f "/dev/mapper/$LUKS_NAME"
            vgcreate "$VG_NAME" "/dev/mapper/$LUKS_NAME"
            lvcreate -L "${SWAP_SIZE}G" "$VG_NAME" -n swap -y
            lvcreate -l 100%FREE "$VG_NAME" -n root -y
            SWAP_PART="/dev/$VG_NAME/swap"
            ROOT_PART="/dev/$VG_NAME/root"
        fi
    elif [ "$picked_cls" = "swap" ]; then
        SWAP_PART="$picked"
        msg "Will reuse $picked as swap."
        warn "You still need a root partition. Pick one or use free space."
        return
    else
        # linux partition — override mode to plain since we're using it directly
        PART_MODE="plain"
        ROOT_PART="$picked"
        warn "Partition $picked ($(lsblk -no FSTYPE "$picked" | head -1)) will be used as root."
        warn "It will be FORMATTED during installation."
        confirm "Proceed with $picked as root?" || exit 1
    fi

    # --- Swap: look for existing swap or ask ---
    if [ -z "$SWAP_PART" ]; then
        local swap_found=""
        for i in "${!candidates[@]}"; do
            if [ "${cand_classes[$i]}" = "swap" ] && [ "${candidates[$i]}" != "$picked" ]; then
                swap_found="${candidates[$i]}"
                break
            fi
        done
        if [ -n "$swap_found" ]; then
            if confirm "Reuse existing swap partition $swap_found?"; then
                SWAP_PART="$swap_found"
            fi
        fi
        if [ -z "$SWAP_PART" ]; then
            info "No swap partition selected. You can create a swap file later."
        fi
    fi

    REUSE_EXISTING=true

    # Ensure we have an EFI partition (may have been set in analyze_partitions)
    if [ -z "$EFI_PART" ]; then
        local efi_parts
        mapfile -t efi_parts < <(lsblk -lpno NAME,PARTTYPE "$DISK" | grep -i "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" | awk '{print $1}')
        if [ ${#efi_parts[@]} -gt 0 ] && [ -n "${efi_parts[0]}" ]; then
            EFI_PART="${efi_parts[0]}"
            EFI_REUSE=true
            msg "Auto-detected EFI partition: $EFI_PART"
        else
            err "No EFI partition found on $DISK. Cannot proceed with reuse."
            err "Wipe the disk and start fresh, or create an EFI partition manually."
            exit 1
        fi
    fi

    echo ""
    header "Reuse Summary"
    echo -e "  Root:  ${BOLD}$ROOT_PART${NC}"
    [ -n "$SWAP_PART" ] && echo -e "  Swap:  ${BOLD}$SWAP_PART${NC}" || echo -e "  Swap:  ${YELLOW}(none)${NC}"
    echo -e "  EFI:   ${BOLD}${EFI_PART:-auto-detect}${NC}"
    [ "$PART_MODE" = "luks" ] && echo -e "  LUKS:  ${BOLD}$LUKS_PART${NC}"
    echo ""
    confirm "Proceed with this layout?" || exit 1
}

shrink_partition() {
    warn "Partition shrinking is a risky operation. Back up data first!"
    echo ""
    lsblk -lpno NAME,SIZE,FSTYPE "$DISK" | tail -n +2 | nl -v 1
    echo ""
    local parts
    mapfile -t parts < <(lsblk -lpno NAME "$DISK" | tail -n +2)

    read -rp "Which partition number to shrink? " pnum
    local target_part="${parts[$((pnum-1))]}"
    local target_fs
    target_fs=$(lsblk -no FSTYPE "$target_part" 2>/dev/null)

    read -rp "New size for $target_part (e.g., 50G, 100G): " new_size

    info "Will shrink $target_part ($target_fs) to $new_size"
    confirm "Proceed with shrink?" || exit 1

    case "$target_fs" in
        ext4)
            umount "$target_part" 2>/dev/null || true
            e2fsck -f "$target_part"
            resize2fs "$target_part" "$new_size"
            msg "Filesystem resized. Now resize the partition with parted."
            parted "$DISK" resizepart "$pnum" "$new_size"
            ;;
        ntfs)
            umount "$target_part" 2>/dev/null || true
            ntfsresize --size "$new_size" "$target_part"
            parted "$DISK" resizepart "$pnum" "$new_size"
            ;;
        *)
            err "Unsupported filesystem for shrinking: $target_fs"
            err "Supported: ext4, ntfs. Please shrink manually."
            exit 1
            ;;
    esac
    msg "Partition shrunk successfully."
}

create_partitions() {
    header "Creating Partitions"
    get_swap_size

    # Helper: get the last partition device on the disk
    get_last_part() {
        partprobe "$DISK" 2>/dev/null
        udevadm settle 2>/dev/null || sleep 2
        lsblk -lpno NAME,TYPE "$DISK" | awk '$2=="part"{p=$1} END{print p}'
    }

    # Ask for volume layout (LVM/LUKS get root+home option)
    local root_size="100%FREE" home_size=""
    if [ "$PART_MODE" != "plain" ]; then
        header "Volume Layout"
        echo -e "  ${BOLD}1)${NC} Single root volume (all space to /)"
        echo -e "  ${BOLD}2)${NC} Root + Home (specify root size, rest goes to /home)"
        echo -e "  ${BOLD}3)${NC} Root + Home (specify both sizes, leave rest as free space)"
        echo ""
        local layout_choice
        while true; do
            read -rp "Choose layout [1/2/3]: " layout_choice
            case "$layout_choice" in 1|2|3) break ;; *) echo "Invalid choice." ;; esac
        done
        if [ "$layout_choice" = "2" ]; then
            read -rp "Root (/) size in GB: " root_size
            root_size="${root_size}G"
        elif [ "$layout_choice" = "3" ]; then
            read -rp "Root (/) size in GB: " root_size
            read -rp "Home (/home) size in GB: " home_size
            root_size="${root_size}G"
            home_size="${home_size}G"
            info "Any remaining space will be offered for additional volumes (e.g., /mnt/data, /srv) after setup."
        fi
    fi

    if [ "$EFI_REUSE" = true ]; then
        msg "Reusing existing EFI partition: $EFI_PART"
    else
        msg "Creating EFI partition (1G)..."
        sgdisk -n 0:0:+1G -t 0:EF00 -c 0:EFI "$DISK"
        EFI_PART=$(get_last_part)
    fi

    # Helper: create LVM volumes with optional home split
    setup_lvm_volumes() {
        local vg="$1"
        lvcreate -L "${SWAP_SIZE}G" "$vg" -n swap -y
        if [ "$root_size" = "100%FREE" ]; then
            lvcreate -l 100%FREE "$vg" -n root -y
        elif [ -n "$home_size" ]; then
            lvcreate -L "$root_size" "$vg" -n root -y
            lvcreate -L "$home_size" "$vg" -n home -y
            HOME_PART="/dev/$vg/home"
        else
            lvcreate -L "$root_size" "$vg" -n root -y
            lvcreate -l 100%FREE "$vg" -n home -y
            HOME_PART="/dev/$vg/home"
        fi
        SWAP_PART="/dev/$vg/swap"
        ROOT_PART="/dev/$vg/root"

        # Offer extra custom volumes
        while true; do
            local remaining
            remaining=$(vgs --noheadings --nosuffix --units g -o vg_free "$vg" 2>/dev/null | xargs | cut -d. -f1)
            if [ "${remaining:-0}" -le 0 ]; then
                info "No free space left in VG."
                break
            fi
            info "${remaining}G free space remaining in VG."
            confirm "Create an additional volume?" || break

            local lv_name lv_size lv_mount
            read -rp "Volume name (e.g., data, media, projects): " lv_name
            while [ -z "$lv_name" ]; do
                read -rp "Volume name cannot be empty: " lv_name
            done
            read -rp "Size in GB (or 'rest' for all remaining): " lv_size
            read -rp "Mount point (e.g., /mnt/data, /srv, /opt): " lv_mount
            while [ -z "$lv_mount" ]; do
                read -rp "Mount point cannot be empty: " lv_mount
            done

            if [ "$lv_size" = "rest" ]; then
                lvcreate -l 100%FREE "$vg" -n "$lv_name" -y
                lv_size="rest"
            else
                lvcreate -L "${lv_size}G" "$vg" -n "$lv_name" -y
                lv_size="${lv_size}G"
            fi
            EXTRA_LV_NAMES+=("$lv_name")
            EXTRA_LV_SIZES+=("$lv_size")
            EXTRA_LV_MOUNTS+=("$lv_mount")
            msg "Created /dev/$vg/$lv_name → $lv_mount"
        done
    }

    case "$PART_MODE" in
        plain)
            msg "Creating swap partition (${SWAP_SIZE}G)..."
            sgdisk -n 0:0:+${SWAP_SIZE}G -t 0:8200 -c 0:swap "$DISK"
            SWAP_PART=$(get_last_part)

            msg "Creating root partition (remaining space)..."
            sgdisk -n 0:0:0 -t 0:8304 -c 0:root "$DISK"
            ROOT_PART=$(get_last_part)
            ;;
        lvm)
            msg "Creating LVM partition (remaining space)..."
            sgdisk -n 0:0:0 -t 0:8E00 -c 0:lvm "$DISK"
            local lvm_part
            lvm_part=$(get_last_part)

            msg "Setting up LVM..."
            wipefs -a "$lvm_part"
            pvcreate -f "$lvm_part"
            vgcreate "$VG_NAME" "$lvm_part"
            setup_lvm_volumes "$VG_NAME"
            ;;
        luks)
            msg "Creating LUKS partition (remaining space)..."
            sgdisk -n 0:0:0 -t 0:8309 -c 0:luks "$DISK"
            LUKS_PART=$(get_last_part)

            msg "Setting up LUKS encryption on $LUKS_PART..."
            warn "You will be asked to set an encryption passphrase."
            wipefs -a "$LUKS_PART"
            # Force-remove any stale mapper device
            if [ -e "/dev/mapper/$LUKS_NAME" ]; then
                warn "Removing stale /dev/mapper/$LUKS_NAME..."
                swapoff -a 2>/dev/null || true
                umount -R /mnt 2>/dev/null || true
                for vg in $(vgs --noheadings -o vg_name 2>/dev/null | xargs); do
                    vgremove -ff "$vg" 2>/dev/null || true
                done
                for dm in $(dmsetup ls 2>/dev/null | awk '{print $1}' | grep -v '^control$' | sort -r); do
                    dmsetup remove -f "$dm" 2>/dev/null || true
                done
            fi
            cryptsetup luksFormat --type luks2 "$LUKS_PART"
            cryptsetup open "$LUKS_PART" "$LUKS_NAME"

            msg "Setting up LVM inside LUKS container..."
            pvcreate -f "/dev/mapper/$LUKS_NAME"
            vgcreate "$VG_NAME" "/dev/mapper/$LUKS_NAME"
            setup_lvm_volumes "$VG_NAME"
            ;;
    esac

    # Show final layout
    echo ""
    header "Partition Layout Summary"
    echo -e "  Mode:      ${BOLD}$PART_MODE${NC}"
    echo -e "  EFI:       ${BOLD}$EFI_PART${NC} $([ "$EFI_REUSE" = true ] && echo "(reused)" || echo "(new)")"
    echo -e "  Swap:      ${BOLD}$SWAP_PART${NC} (${SWAP_SIZE}G)"
    echo -e "  Root:      ${BOLD}$ROOT_PART${NC}"
    [ -n "$HOME_PART" ] && echo -e "  Home:      ${BOLD}$HOME_PART${NC}"
    for i in "${!EXTRA_LV_NAMES[@]}"; do
        echo -e "  ${EXTRA_LV_MOUNTS[$i]}:  ${BOLD}/dev/$VG_NAME/${EXTRA_LV_NAMES[$i]}${NC} (${EXTRA_LV_SIZES[$i]})"
    done
    [ "$PART_MODE" = "luks" ] && echo -e "  LUKS dev:  ${BOLD}$LUKS_PART${NC}"
    [ "$PART_MODE" != "plain" ] && echo -e "  VG:        ${BOLD}$VG_NAME${NC}"
    echo ""

    warn "FINAL CONFIRMATION: This will format and write partitions."
    confirm "Proceed with this layout?" || { cleanup; exit 1; }
}

# ============================================================
# PHASE 4: Format & Mount
# ============================================================
format_partitions() {
    header "Formatting Partitions"

    if [ "$EFI_REUSE" = false ]; then
        msg "Formatting EFI partition ($EFI_PART) as FAT32..."
        mkfs.fat -F 32 "$EFI_PART"
    else
        info "Skipping EFI format (reusing existing partition)."
    fi

    if [ "$REUSE_EXISTING" = true ]; then
        warn "Root partition $ROOT_PART will be FORMATTED (all data erased)."
        confirm "Format $ROOT_PART as ext4?" || exit 1
    fi

    msg "Formatting root partition ($ROOT_PART) as ext4..."
    mkfs.ext4 -F "$ROOT_PART"

    if [ -n "$HOME_PART" ]; then
        msg "Formatting home partition ($HOME_PART) as ext4..."
        mkfs.ext4 -F "$HOME_PART"
    fi

    if [ -n "$SWAP_PART" ]; then
        msg "Setting up swap ($SWAP_PART)..."
        mkswap "$SWAP_PART"
    else
        info "No swap partition. You can create a swap file post-install."
    fi

    # Format extra volumes
    for i in "${!EXTRA_LV_NAMES[@]}"; do
        local lv="/dev/$VG_NAME/${EXTRA_LV_NAMES[$i]}"
        msg "Formatting $lv (${EXTRA_LV_MOUNTS[$i]}) as ext4..."
        mkfs.ext4 -F "$lv"
    done
}

mount_partitions() {
    header "Mounting Partitions"
    msg "Mounting root to /mnt..."
    mount "$ROOT_PART" /mnt

    if [ -n "$HOME_PART" ]; then
        msg "Mounting home to /mnt/home..."
        mount --mkdir "$HOME_PART" /mnt/home
    fi

    msg "Mounting EFI to /mnt/boot..."
    mount --mkdir "$EFI_PART" /mnt/boot

    msg "Enabling swap..."
    if [ -n "$SWAP_PART" ]; then
        swapon "$SWAP_PART"
    else
        info "No swap partition to enable."
    fi

    # Mount extra volumes
    for i in "${!EXTRA_LV_NAMES[@]}"; do
        local lv="/dev/$VG_NAME/${EXTRA_LV_NAMES[$i]}"
        local mnt="/mnt${EXTRA_LV_MOUNTS[$i]}"
        msg "Mounting $lv to $mnt..."
        mount --mkdir "$lv" "$mnt"
    done

    msg "Current mount layout:"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT "$DISK"

    # Detect other Linux boot entries on reused EFI partition
    if [ "$EFI_REUSE" = true ] && [ -d /mnt/boot ]; then
        # Show what's already on the EFI partition so the user knows
        local other_entries=()
        if [ -d /mnt/boot/loader/entries ]; then
            mapfile -t other_entries < <(find /mnt/boot/loader/entries -name '*.conf' 2>/dev/null)
        fi
        local other_efi_dirs=()
        if [ -d /mnt/boot/EFI ]; then
            mapfile -t other_efi_dirs < <(find /mnt/boot/EFI -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
        fi

        if [ ${#other_entries[@]} -gt 0 ] || [ ${#other_efi_dirs[@]} -gt 0 ]; then
            info "Existing boot content on EFI partition:"
            for e in "${other_entries[@]}"; do
                local title
                title=$(grep -i '^title' "$e" 2>/dev/null | head -1 | sed 's/^title[[:space:]]*//')
                echo -e "  ${CYAN}Entry: $(basename "$e")${NC}  (${title:-untitled})"
            done
            for d in "${other_efi_dirs[@]}"; do
                echo -e "  ${CYAN}EFI dir: $(basename "$d")${NC}"
            done
            echo ""
            info "These will be PRESERVED. Arch will install alongside them."
        fi

        # Only remove OUR OWN previous Arch files (identified by hostname tag)
        local our_tag="/mnt/boot/.arch-install-${HOSTNAME_VAL:-new}"
        if [ -f "$our_tag" ]; then
            warn "Found a previous Arch install tagged '${HOSTNAME_VAL:-new}' on this EFI partition."
            info "Its boot files will be replaced by this installation."
        fi
    fi
}

# ============================================================
# PHASE 4b: WiFi Config Copy
# ============================================================
copy_wifi_config() {
    header "WiFi Configuration"

    # Check if iwd is running and has profiles
    if [ ! -d /var/lib/iwd ] || [ -z "$(ls -A /var/lib/iwd/*.psk 2>/dev/null)$(ls -A /var/lib/iwd/*.open 2>/dev/null)$(ls -A /var/lib/iwd/*.8021x 2>/dev/null)" ]; then
        info "No iwd WiFi profiles found (likely using ethernet). Skipping."
        return
    fi

    msg "Detected iwd WiFi profiles:"
    find /var/lib/iwd -maxdepth 1 -name '*.psk' -o -name '*.open' -o -name '*.8021x' | while read -r f; do
        echo -e "  ${CYAN}$(basename "$f")${NC}"
    done

    if confirm "Copy WiFi profiles to new system?"; then
        mkdir -p /mnt/var/lib/iwd
        find /var/lib/iwd -maxdepth 1 \( -name '*.psk' -o -name '*.open' -o -name '*.8021x' \) -exec cp {} /mnt/var/lib/iwd/ \;
        chmod 600 /mnt/var/lib/iwd/*
        chmod 700 /mnt/var/lib/iwd
        msg "WiFi profiles copied. Network should work on first boot."
    fi
}

# ============================================================
# PHASE 5: Base System Installation
# ============================================================
install_base() {
    header "Base System Installation"

    # Detect CPU for microcode
    if grep -q "GenuineIntel" /proc/cpuinfo; then
        CPU_UCODE="intel-ucode"
    elif grep -q "AuthenticAMD" /proc/cpuinfo; then
        CPU_UCODE="amd-ucode"
    fi
    [ -n "$CPU_UCODE" ] && info "Detected CPU microcode package: $CPU_UCODE"

    msg "Running pacstrap..."
    local pkgs="base linux linux-firmware base-devel"
    [ -n "$CPU_UCODE" ] && pkgs="$pkgs $CPU_UCODE"
    [ "$PART_MODE" != "plain" ] && pkgs="$pkgs lvm2"
    [ "$PART_MODE" = "luks" ] && pkgs="$pkgs cryptsetup"
    # shellcheck disable=SC2086
    if ! pacstrap -K /mnt $pkgs; then
        warn "pacstrap failed — checking for conflicting boot files..."
        # Only back up files if they point to a DIFFERENT root (not ours)
        local backup_dir="/mnt/root/boot-backup-$(date +%Y%m%d%H%M%S)"
        local backed_up=false
        for f in /mnt/boot/vmlinuz-linux /mnt/boot/initramfs-linux.img /mnt/boot/initramfs-linux-fallback.img /mnt/boot/intel-ucode.img /mnt/boot/amd-ucode.img; do
            if [ -e "$f" ]; then
                mkdir -p "$backup_dir"
                mv "$f" "$backup_dir/"
                warn "Backed up $(basename "$f") (may belong to another install)"
                backed_up=true
            fi
        done
        if [ "$backed_up" = true ]; then
            warn "Backed up conflicting files to $backup_dir"
            warn "If another Linux install used these, restore them after this install."
        fi
        # shellcheck disable=SC2086
        pacstrap -K /mnt $pkgs
    fi

    # Offer to save a copy of this installer script into the new system
    local self_path
    self_path="$(readlink -f "$0")"
    if [ -f "$self_path" ] && confirm "Save a copy of this installer to /root/arch-install.sh on the new system?"; then
        cp "$self_path" /mnt/root/arch-install.sh
        chmod +x /mnt/root/arch-install.sh
        msg "Installer script saved to /root/arch-install.sh on new system."
    fi

    msg "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
    info "Generated /mnt/etc/fstab:"
    cat /mnt/etc/fstab
}

# ============================================================
# PHASE 6: System Configuration (chroot)
# ============================================================
gather_config() {
    header "System Configuration"

    # Timezone
    info "Select timezone (e.g., America/New_York, Europe/London, Asia/Dubai):"
    read -rp "Timezone: " TIMEZONE
    while [ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]; do
        warn "Invalid timezone. Examples: US/Eastern, Europe/Berlin, Asia/Kolkata"
        read -rp "Timezone: " TIMEZONE
    done

    # Locale
    info "Select locale (e.g., en_US.UTF-8, en_GB.UTF-8, de_DE.UTF-8):"
    read -rp "Locale [en_US.UTF-8]: " LOCALE
    LOCALE="${LOCALE:-en_US.UTF-8}"

    # Keymap
    info "Console keymap — type a search term to filter (e.g., us, colemak, dvorak, uk):"
    local keymap_search
    while true; do
        read -rp "Search keymaps [us]: " keymap_search
        keymap_search="${keymap_search:-us}"
        local -a matches
        mapfile -t matches < <(localectl list-keymaps 2>/dev/null | grep -i "$keymap_search")
        if [ ${#matches[@]} -eq 0 ]; then
            warn "No keymaps matching '$keymap_search'. Try again."
            continue
        fi
        echo ""
        for i in "${!matches[@]}"; do
            echo -e "  ${BOLD}$((i+1)))${NC} ${matches[$i]}"
        done
        echo ""
        if [ ${#matches[@]} -eq 1 ]; then
            KEYMAP="${matches[0]}"
            msg "Selected keymap: $KEYMAP"
            break
        fi
        local kc
        read -rp "Pick a keymap [1-${#matches[@]}] or 's' to search again: " kc
        if [ "$kc" = "s" ]; then continue; fi
        if [[ "$kc" =~ ^[0-9]+$ ]] && [ "$kc" -ge 1 ] && [ "$kc" -le "${#matches[@]}" ]; then
            KEYMAP="${matches[$((kc-1))]}"
            msg "Selected keymap: $KEYMAP"
            break
        fi
        echo "Invalid choice."
    done

    # X11/Wayland keyboard layout (separate from console keymap)
    # X11/Wayland keyboard layout (read from XKB rules, not localectl)
    local xkb_file="/usr/share/X11/xkb/rules/base.lst"
    info "X11 keyboard layout — type a search term to filter (e.g., us, fr, de, gb):"
    while true; do
        local layout_search
        read -rp "Search layouts [us]: " layout_search
        layout_search="${layout_search:-us}"
        local -a layout_matches
        mapfile -t layout_matches < <(sed -n '/^! layout/,/^!/p' "$xkb_file" | grep -v '^!' | awk '{print $1}' | grep -i "$layout_search")
        if [ ${#layout_matches[@]} -eq 0 ]; then
            warn "No layouts matching '$layout_search'. Try again."
            continue
        fi
        local j=1
        for lm in "${layout_matches[@]}"; do echo "  $j) $lm"; j=$((j+1)); done
        if [ ${#layout_matches[@]} -eq 1 ]; then
            KB_LAYOUT="${layout_matches[0]}"
            msg "Selected layout: $KB_LAYOUT"
            break
        fi
        local lp
        read -rp "Pick [1-${#layout_matches[@]}] or 's' to search again: " lp
        if [ "$lp" = "s" ]; then continue; fi
        if [[ "$lp" =~ ^[0-9]+$ ]] && [ "$lp" -ge 1 ] && [ "$lp" -le "${#layout_matches[@]}" ]; then
            KB_LAYOUT="${layout_matches[$((lp-1))]}"
            msg "Selected layout: $KB_LAYOUT"
            break
        fi
        echo "Invalid choice."
    done

    # X11/Wayland layout variant (optional)
    local -a variant_list
    mapfile -t variant_list < <(sed -n '/^! variant/,/^!/p' "$xkb_file" | grep -v '^!' | grep "^ *[^ ]* *${KB_LAYOUT}:" | awk '{print $1}')
    if [ ${#variant_list[@]} -gt 0 ]; then
        info "Available variants for '$KB_LAYOUT' (Enter to skip for default):"
        local j=1
        for vm in "${variant_list[@]}"; do echo "  $j) $vm"; j=$((j+1)); done
        local vp
        read -rp "Pick variant [1-${#variant_list[@]}] or Enter to skip: " vp
        if [[ "$vp" =~ ^[0-9]+$ ]] && [ "$vp" -ge 1 ] && [ "$vp" -le "${#variant_list[@]}" ]; then
            KB_VARIANT="${variant_list[$((vp-1))]}"
        fi
    fi

    if [ -n "$KB_VARIANT" ]; then
        msg "X11 keyboard: $KB_LAYOUT ($KB_VARIANT)"
    else
        msg "X11 keyboard: $KB_LAYOUT"
    fi

    # Hostname
    read -rp "Hostname: " HOSTNAME_VAL
    while [ -z "$HOSTNAME_VAL" ]; do
        warn "Hostname cannot be empty."
        read -rp "Hostname: " HOSTNAME_VAL
    done
}

configure_system() {
    header "Applying System Configuration (chroot)"

    # Build the chroot script
    local hooks="base udev autodetect microcode modconf kms keyboard keymap consolefont block"
    case "$PART_MODE" in
        lvm)   hooks="$hooks lvm2 filesystems fsck" ;;
        luks)  hooks="$hooks encrypt lvm2 filesystems fsck" ;;
        plain) hooks="$hooks filesystems fsck" ;;
    esac

    # Scripts go in /mnt/root to avoid arch-chroot tmpfs shadow
    cat > /mnt/root/chroot-setup.sh << CHROOTEOF
#!/bin/bash
set -euo pipefail

# Timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Locale
sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf

# Console keymap
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# Hostname
echo "${HOSTNAME_VAL}" > /etc/hostname

# mkinitcpio hooks
sed -i "s/^HOOKS=.*/HOOKS=(${hooks})/" /etc/mkinitcpio.conf
mkinitcpio -P

# Root password
echo "Set root password:"
passwd

echo "System configuration complete."
CHROOTEOF

    chmod +x /mnt/root/chroot-setup.sh
    arch-chroot /mnt /usr/bin/bash /root/chroot-setup.sh
    rm /mnt/root/chroot-setup.sh
}

# ============================================================
# PHASE 7: systemd-boot & Post-install
# ============================================================
setup_bootloader() {
    header "systemd-boot Setup"

    # Detect if another bootloader (GRUB) is already managing boot
    local existing_grub=false
    local grub_distro=""
    if [ "$EFI_REUSE" = true ]; then
        for grub_efi in /mnt/boot/EFI/*/grubx64.efi /mnt/boot/EFI/*/shimx64.efi; do
            if [ -f "$grub_efi" ]; then
                existing_grub=true
                grub_distro=$(basename "$(dirname "$grub_efi")")
                break
            fi
        done
    fi

    if [ "$existing_grub" = true ]; then
        warn "An existing GRUB bootloader was found (${grub_distro})."
        info "You have two options:"
        echo ""
        echo -e "  ${BOLD}1)${NC} Install systemd-boot (replaces GRUB as default, chainloads other OSes)"
        echo -e "  ${BOLD}2)${NC} Skip — keep existing GRUB, add Arch entry to it manually after reboot"
        echo ""
        info "Option 2: after reboot into ${grub_distro}, run 'sudo update-grub' or 'grub-mkconfig' to auto-detect Arch."
        echo ""
        local boot_choice
        while true; do
            read -rp "Choose [1/2]: " boot_choice
            case "$boot_choice" in 1|2) break ;; *) echo "Invalid choice." ;; esac
        done

        if [ "$boot_choice" = "2" ]; then
            msg "Skipping systemd-boot installation. Existing GRUB preserved."

            # Write a custom GRUB entry for Arch on the EFI partition
            local grub_custom="/mnt/boot/EFI/${grub_distro}/grub.cfg"
            local efi_uuid
            efi_uuid=$(blkid -s UUID -o value "$EFI_PART")

            # Build the kernel options line
            local grub_opts=""
            case "$PART_MODE" in
                plain)
                    local root_uuid
                    root_uuid=$(blkid -s UUID -o value "$ROOT_PART")
                    grub_opts="root=UUID=${root_uuid} rw"
                    ;;
                lvm)
                    grub_opts="root=/dev/${VG_NAME}/root rw"
                    ;;
                luks)
                    local luks_uuid
                    luks_uuid=$(blkid -s UUID -o value "$LUKS_PART")
                    grub_opts="cryptdevice=UUID=${luks_uuid}:${LUKS_NAME} root=/dev/${VG_NAME}/root rw"
                    ;;
            esac

            local initrd_line="initrd"
            [ -n "$CPU_UCODE" ] && initrd_line="initrd /${CPU_UCODE}.img /initramfs-linux.img" || initrd_line="initrd /initramfs-linux.img"

            # Append Arch entry to the distro's grub.cfg
            if [ -f "$grub_custom" ]; then
                # Remove any previous Arch entry we added
                sed -i '/### BEGIN Arch Linux (auto-added) ###/,/### END Arch Linux ###/d' "$grub_custom"

                cat >> "$grub_custom" << GRUBEOF

### BEGIN Arch Linux (auto-added) ###
menuentry 'Arch Linux' {
    search --no-floppy --fs-uuid --set=root ${efi_uuid}
    linux /vmlinuz-linux ${grub_opts}
    ${initrd_line}
}
menuentry 'Arch Linux (fallback)' {
    search --no-floppy --fs-uuid --set=root ${efi_uuid}
    linux /vmlinuz-linux ${grub_opts}
    initrd /initramfs-linux-fallback.img
}
### END Arch Linux ###
GRUBEOF
                msg "Added Arch entries to ${grub_distro}'s grub.cfg"
            else
                warn "Could not find ${grub_custom}"
                info "After reboot, run 'sudo update-grub' from ${grub_distro} to detect Arch."
            fi
            return
        fi
    fi

    # Generate a unique entry ID to avoid collisions with other Linux installs
    local entry_id="arch"
    if [ "$EFI_REUSE" = true ]; then
        # Check if arch.conf already exists from another install
        if [ -f /mnt/boot/loader/entries/arch.conf ]; then
            local existing_root
            existing_root=$(grep -oP 'root=\S+' /mnt/boot/loader/entries/arch.conf 2>/dev/null | head -1)
            # If the existing entry points to a different root, namespace ours
            if [ -n "$existing_root" ] && ! echo "$existing_root" | grep -q "$ROOT_PART" && \
               ! echo "$existing_root" | grep -q "$VG_NAME/root"; then
                entry_id="arch-${HOSTNAME_VAL}"
                info "Another Arch boot entry exists. Using namespaced entry: ${entry_id}.conf"
            fi
        fi
    fi

    # Build kernel options based on partition mode
    local root_opts=""
    case "$PART_MODE" in
        plain)
            local root_uuid
            root_uuid=$(blkid -s UUID -o value "$ROOT_PART")
            root_opts="root=UUID=${root_uuid} rw"
            ;;
        lvm)
            root_opts="root=/dev/$VG_NAME/root rw"
            ;;
        luks)
            local luks_uuid
            luks_uuid=$(blkid -s UUID -o value "$LUKS_PART")
            root_opts="cryptdevice=UUID=${luks_uuid}:${LUKS_NAME} root=/dev/$VG_NAME/root rw"
            ;;
    esac

    local ucode_initrd=""
    [ -n "$CPU_UCODE" ] && ucode_initrd="initrd  /${CPU_UCODE}.img"

    cat > /mnt/root/boot-setup.sh << BOOTEOF
#!/bin/bash
set -euo pipefail

# Install systemd-boot (safe — updates existing install or adds new)
bootctl install

# Loader config — only write if we're the first or if no loader.conf exists
if [ ! -f /boot/loader/loader.conf ]; then
    cat > /boot/loader/loader.conf << EOF
default ${entry_id}.conf
timeout 3
console-mode max
editor  no
EOF
else
    # Ensure timeout is set so user can pick between OSes
    if ! grep -q '^timeout' /boot/loader/loader.conf; then
        echo "timeout 3" >> /boot/loader/loader.conf
    fi
fi

# Arch entry
cat > /boot/loader/entries/${entry_id}.conf << EOF
title   Arch Linux${entry_id:+ (${HOSTNAME_VAL})}
linux   /vmlinuz-linux
${ucode_initrd}
initrd  /initramfs-linux.img
options ${root_opts}
EOF

# Fallback entry
cat > /boot/loader/entries/${entry_id}-fallback.conf << EOF
title   Arch Linux${entry_id:+ (${HOSTNAME_VAL})} (fallback)
linux   /vmlinuz-linux
${ucode_initrd}
initrd  /initramfs-linux-fallback.img
options ${root_opts}
EOF

# Tag this install so we can identify our own files later
echo "${entry_id}" > /boot/.arch-install-${HOSTNAME_VAL}

# --- Auto-detect other OS bootloaders and create chainload entries ---

# Windows Boot Manager
if [ -f /boot/EFI/Microsoft/Boot/bootmgfw.efi ]; then
    cat > /boot/loader/entries/windows.conf << EOF
title   Windows Boot Manager
efi     /EFI/Microsoft/Boot/bootmgfw.efi
EOF
    echo "Added Windows boot entry."
fi

# Detect other Linux distros by their EFI directories
declare -A distro_efi=(
    [ubuntu]="/EFI/ubuntu/shimx64.efi"
    [fedora]="/EFI/fedora/shimx64.efi"
    [opensuse]="/EFI/opensuse/shimx64.efi"
    [debian]="/EFI/debian/shimx64.efi"
    [pop-os]="/EFI/Pop_OS-*/shimx64.efi"
    [manjaro]="/EFI/Manjaro/grubx64.efi"
    [endeavouros]="/EFI/endeavouros/grubx64.efi"
    [linuxmint]="/EFI/linuxmint/shimx64.efi"
    [zorin]="/EFI/zorin/shimx64.efi"
    [centos]="/EFI/centos/shimx64.efi"
    [rocky]="/EFI/rocky/shimx64.efi"
    [alma]="/EFI/almalinux/shimx64.efi"
)

for distro in "\${!distro_efi[@]}"; do
    # Use glob expansion for patterns like Pop_OS-*
    for efi_path in /boot\${distro_efi[\$distro]}; do
        if [ -f "\$efi_path" ]; then
            # Convert absolute path to EFI-relative path
            local_efi="\${efi_path#/boot}"
            entry_file="/boot/loader/entries/\${distro}.conf"
            if [ ! -f "\$entry_file" ]; then
                cat > "\$entry_file" << EOF
title   \$(echo "\$distro" | sed 's/.*/\u&/') Linux
efi     \${local_efi}
EOF
                echo "Added \$distro boot entry (\$local_efi)."
            fi
            break  # only first match per distro
        fi
    done
done

# Fallback: detect any GRUB EFI binary we haven't already covered
for grub_efi in /boot/EFI/*/grubx64.efi; do
    [ -f "\$grub_efi" ] || continue
    dir_name=\$(basename "\$(dirname "\$grub_efi")")
    # Skip if we already created an entry for this distro
    [ -f "/boot/loader/entries/\${dir_name,,}.conf" ] && continue
    [ "\$dir_name" = "BOOT" ] && continue
    local_efi="\${grub_efi#/boot}"
    cat > "/boot/loader/entries/\${dir_name,,}.conf" << EOF
title   \${dir_name} Linux (GRUB)
efi     \${local_efi}
EOF
    echo "Added \$dir_name boot entry (\$local_efi)."
done

echo "systemd-boot configured (entry: ${entry_id}.conf)."
BOOTEOF

    chmod +x /mnt/root/boot-setup.sh
    arch-chroot /mnt /usr/bin/bash /root/boot-setup.sh
    rm /mnt/root/boot-setup.sh
}

install_packages() {
    header "Window Manager / Desktop Selection"

    echo -e "  ${BOLD}1)${NC} i3         — Tiling WM (X11) + polybar, picom, rofi, alacritty, flameshot"
    echo -e "  ${BOLD}2)${NC} i3 Custom  — Hafeezh's full rice (i3 + 14 polybar scripts, sounds, privacy monitor)"
    echo -e "  ${BOLD}3)${NC} Sway       — Tiling compositor (Wayland, i3-compatible) + waybar, wofi, foot"
    echo -e "  ${BOLD}4)${NC} Hyprland   — Animated compositor (Wayland) + waybar, wofi, foot"
    echo -e "  ${BOLD}5)${NC} KDE Plasma — Full desktop (Windows-like, great for switchers)"
    echo -e "  ${BOLD}6)${NC} None       — Base system only, no graphical environment"
    echo ""
    while true; do
        read -rp "Select environment [1-6]: " wm_choice
        case "$wm_choice" in
            1) WM_CHOICE="i3"; break ;;
            2) WM_CHOICE="user_custom"; break ;;
            3) WM_CHOICE="sway"; break ;;
            4) WM_CHOICE="hyprland"; break ;;
            5) WM_CHOICE="kde"; break ;;
            6) WM_CHOICE="none"; break ;;
            *) echo "Invalid choice." ;;
        esac
    done
    msg "Selected: $WM_CHOICE"

    # --- GPU driver detection ---
    header "GPU Driver Detection"
    local gpu_pkgs=""
    if lspci 2>/dev/null | grep -qi "intel.*graphics\|intel.*gpu\|UHD\|Iris"; then
        info "Intel GPU detected."
        gpu_pkgs="mesa vulkan-intel intel-media-driver sof-firmware"
    fi
    if lspci 2>/dev/null | grep -qi "amd.*radeon\|amd.*graphics\|ATI\|RADV"; then
        info "AMD GPU detected."
        gpu_pkgs="$gpu_pkgs mesa vulkan-radeon sof-firmware"
    fi
    if lspci 2>/dev/null | grep -qi "nvidia"; then
        info "NVIDIA GPU detected."
        echo -e "  ${BOLD}1)${NC} Open-source (nouveau) — works out of the box, lower performance"
        echo -e "  ${BOLD}2)${NC} Proprietary (nvidia)  — better performance, needs DKMS"
        local nv_choice
        while true; do
            read -rp "NVIDIA driver [1/2]: " nv_choice
            case "$nv_choice" in
                1) gpu_pkgs="$gpu_pkgs mesa"; break ;;
                2) gpu_pkgs="$gpu_pkgs nvidia nvidia-utils nvidia-settings"; break ;;
                *) echo "Invalid choice." ;;
            esac
        done
    fi
    if [ -z "$gpu_pkgs" ]; then
        info "No specific GPU detected. Installing generic mesa drivers."
        gpu_pkgs="mesa"
    fi
    msg "GPU packages: $gpu_pkgs"

    header "Installing Packages"

    # Base packages always installed
    local base_pkgs="openssh neovim networkmanager dhcpcd iwd git wget curl sudo"
    base_pkgs="$base_pkgs ttf-dejavu ttf-liberation noto-fonts"
    base_pkgs="$base_pkgs pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol"
    base_pkgs="$base_pkgs brightnessctl fastfetch thunar ffmpeg"

    # WM-specific packages
    local wm_pkgs=""
    case "$WM_CHOICE" in
        i3)
            wm_pkgs="i3-wm i3status i3lock polybar dunst rofi picom feh alacritty flameshot"
            wm_pkgs="$wm_pkgs xorg-server xorg-xinit xorg-xrandr xorg-xsetroot dex"
            wm_pkgs="$wm_pkgs network-manager-applet xss-lock"
            ;;
        user_custom)
            wm_pkgs="i3-wm i3status i3lock polybar dunst rofi picom feh kitty flameshot"
            wm_pkgs="$wm_pkgs xorg-server xorg-xinit xorg-xrandr xorg-xsetroot dex"
            wm_pkgs="$wm_pkgs network-manager-applet xss-lock lm_sensors openvpn expect"
            ;;
        sway)
            wm_pkgs="sway swaylock swayidle waybar mako wofi foot grim slurp"
            wm_pkgs="$wm_pkgs xorg-xwayland"
            ;;
        hyprland)
            wm_pkgs="hyprland waybar mako wofi foot grim slurp"
            wm_pkgs="$wm_pkgs xorg-xwayland"
            ;;
        kde)
            wm_pkgs="plasma-meta kde-applications-meta sddm"
            ;;
        none)
            info "No graphical packages will be installed."
            ;;
    esac

    cat > /mnt/root/pkg-setup.sh << PKGEOF
#!/bin/bash
set -euo pipefail
pacman -S --noconfirm --needed $base_pkgs $gpu_pkgs $wm_pkgs
systemctl enable sshd
systemctl enable NetworkManager
PKGEOF

    # KDE needs SDDM display manager
    if [ "$WM_CHOICE" = "kde" ]; then
        echo 'systemctl enable sddm' >> /mnt/root/pkg-setup.sh
    fi

    echo 'echo "Packages installed and services enabled."' >> /mnt/root/pkg-setup.sh

    chmod +x /mnt/root/pkg-setup.sh
    arch-chroot /mnt /usr/bin/bash /root/pkg-setup.sh
    rm /mnt/root/pkg-setup.sh

    # --- Install bundled custom fonts ---
    if [ -d "$SCRIPT_DIR/fonts" ] && [ -n "$(ls -A "$SCRIPT_DIR/fonts/" 2>/dev/null)" ]; then
        msg "Installing custom fonts..."
        mkdir -p /mnt/usr/local/share/fonts/custom
        cp "$SCRIPT_DIR/fonts/"*.ttf /mnt/usr/local/share/fonts/custom/ 2>/dev/null || true
        arch-chroot /mnt fc-cache -fv >/dev/null 2>&1
        msg "Custom fonts installed."
    fi

    # --- Wine / Windows compatibility ---
    if [ "$WM_CHOICE" != "none" ]; then
        echo ""
        info "Do you need to run Windows applications (.exe files)?"
        info "This installs Wine (compatibility layer) and Bottles (friendly GUI manager)."
        if confirm "Install Windows app support (Wine + Bottles)?"; then
            cat > /mnt/root/wine-setup.sh << 'WINEEOF'
#!/bin/bash
set -euo pipefail
# Enable multilib repo for 32-bit Wine libs
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    echo -e '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist' >> /etc/pacman.conf
fi
pacman -Sy --noconfirm --needed wine wine-mono wine-gecko winetricks
# Bottles is in AUR — install if yay/paru available, otherwise skip
echo "Wine installed. For Bottles (GUI manager), install from AUR after reboot:"
echo "  yay -S bottles"
WINEEOF
            chmod +x /mnt/root/wine-setup.sh
            arch-chroot /mnt /usr/bin/bash /root/wine-setup.sh
            rm /mnt/root/wine-setup.sh
            msg "Wine installed. Install 'bottles' from AUR after first boot for a nice GUI."
        fi
    fi

    # --- AUR helper ---
    if [ "$WM_CHOICE" != "none" ]; then
        echo ""
        header "AUR Helper"
        echo -e "  ${BOLD}1)${NC} yay   — Yet Another Yogurt (Go, most popular)"
        echo -e "  ${BOLD}2)${NC} paru  — Feature-rich AUR helper (Rust)"
        echo -e "  ${BOLD}3)${NC} None  — Skip, install manually later"
        local aur_choice
        while true; do
            read -rp "Select AUR helper [1-3]: " aur_choice
            case "$aur_choice" in
                1) AUR_HELPER="yay"; break ;;
                2) AUR_HELPER="paru"; break ;;
                3) AUR_HELPER="none"; break ;;
                *) echo "Invalid choice." ;;
            esac
        done
        if [ "$AUR_HELPER" != "none" ]; then
            msg "AUR helper '$AUR_HELPER' will be installed during user setup."
        fi
    fi

    # --- Browser selection ---
    if [ "$WM_CHOICE" != "none" ]; then
        echo ""
        header "Browser Selection"
        echo -e "  ${BOLD}1)${NC} Firefox"
        echo -e "  ${BOLD}2)${NC} LibreWolf  (Firefox fork, privacy-focused)"
        echo -e "  ${BOLD}3)${NC} Chromium   (open-source Chrome)"
        echo -e "  ${BOLD}4)${NC} Brave      (Chromium + ad-blocking)"
        echo -e "  ${BOLD}5)${NC} None       — Install later"
        local browser_choice
        while true; do
            read -rp "Select browser [1-5]: " browser_choice
            case "$browser_choice" in
                1) BROWSER_PKG="firefox"; break ;;
                2) BROWSER_PKG="librewolf-bin"; break ;;
                3) BROWSER_PKG="chromium"; break ;;
                4) BROWSER_PKG="brave-bin"; break ;;
                5) BROWSER_PKG=""; break ;;
                *) echo "Invalid choice." ;;
            esac
        done
        if [ -n "$BROWSER_PKG" ]; then
            # firefox and chromium are in official repos; librewolf-bin and brave-bin are AUR
            case "$BROWSER_PKG" in
                firefox|chromium)
                    arch-chroot /mnt pacman -S --noconfirm --needed "$BROWSER_PKG"
                    ;;
                *)
                    msg "Browser '$BROWSER_PKG' is in AUR — will be installed during user setup."
                    ;;
            esac
        fi
    fi

    # --- eGPU setup (user_custom only) ---
    if [ "$WM_CHOICE" = "user_custom" ]; then
        echo ""
        info "Do you use an NVIDIA eGPU via Thunderbolt (Razer Core X)?"
        if confirm "Install eGPU auto-setup (bolt auth + nvidia driver loading + xorg config)?"; then
            EGPU_SETUP="yes"
            msg "eGPU setup will be deployed during user setup."
        fi
    fi
}

# ============================================================
# PHASE 7b: User Creation & Config Deployment
# ============================================================
setup_user_and_rice() {
    header "User Account Setup"

    local username
    # Check for existing non-root users from a previous run
    local existing_user
    existing_user=$(arch-chroot /mnt awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd 2>/dev/null | head -1)
    if [ -n "$existing_user" ]; then
        info "Existing user found: $existing_user"
        if confirm "Continue with '$existing_user'?"; then
            username="$existing_user"
        else
            read -rp "Create non-root username: " username
            while [ -z "$username" ]; do
                warn "Username cannot be empty."
                read -rp "Username: " username
            done
        fi
    else
        read -rp "Create non-root username: " username
        while [ -z "$username" ]; do
            warn "Username cannot be empty."
            read -rp "Username: " username
        done
    fi

    # Deploy bundled configs for the selected WM
    if [ "$WM_CHOICE" != "none" ] && [ -d "$SCRIPT_DIR/configs/$WM_CHOICE" ]; then
        msg "Deploying $WM_CHOICE config templates..."
        cp -r "$SCRIPT_DIR/configs/$WM_CHOICE" /mnt/root/wm-configs
    fi

    # Deploy eGPU files if requested
    if [ "$EGPU_SETUP" = "yes" ] && [ -d "$SCRIPT_DIR/configs/user_custom/egpu" ]; then
        msg "Deploying eGPU setup files..."
        cp "$SCRIPT_DIR/configs/user_custom/egpu/nvidia-egpu-setup.sh" /mnt/usr/local/bin/nvidia-egpu-setup.sh
        chmod +x /mnt/usr/local/bin/nvidia-egpu-setup.sh
        cp "$SCRIPT_DIR/configs/user_custom/egpu/nvidia-egpu.service" /mnt/etc/systemd/system/nvidia-egpu.service
        mkdir -p /mnt/etc/X11/xorg.conf.d
        cp "$SCRIPT_DIR/configs/user_custom/egpu/10-nvidia-egpu.conf" /mnt/etc/X11/xorg.conf.d/10-nvidia-egpu.conf
    fi

    # Build session hint
    local session_hint=""
    case "$WM_CHOICE" in
        i3|user_custom) session_hint="i3 starts automatically after boot." ;;
        sway)           session_hint="Sway starts automatically after boot." ;;
        hyprland)       session_hint="Hyprland starts automatically after boot." ;;
        kde)            session_hint="KDE starts automatically via SDDM." ;;
        none)           session_hint="No graphical environment installed." ;;
    esac

    cat > /mnt/root/user-setup.sh << USEREOF
#!/bin/bash
set -euo pipefail

if id "${username}" &>/dev/null; then
    echo "User '${username}' already exists."
    read -rp "Continue with existing user? [y/n]: " reuse_user
    if [ "\$reuse_user" != "y" ]; then
        echo "Aborting user setup."
        exit 1
    fi
    usermod -aG wheel ${username}
else
    useradd -m -G wheel -s /bin/bash ${username}
fi
echo "Set password for ${username}:"
passwd ${username}

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Deploy WM configs from bundled templates
if [ -d /root/wm-configs ]; then
    home="/home/${username}"
    cfg="\$home/.config"
    mkdir -p "\$cfg"

    case "${WM_CHOICE}" in
        i3)
            mkdir -p "\$cfg/i3" "\$cfg/polybar" "\$cfg/picom" "\$cfg/dunst" "\$cfg/rofi" "\$cfg/alacritty"
            cp /root/wm-configs/config "\$cfg/i3/config"
            cp /root/wm-configs/polybar/* "\$cfg/polybar/"
            cp /root/wm-configs/picom/* "\$cfg/picom/"
            cp /root/wm-configs/dunst/* "\$cfg/dunst/"
            cp /root/wm-configs/rofi/* "\$cfg/rofi/"
            cp /root/wm-configs/alacritty/* "\$cfg/alacritty/"
            chmod +x "\$cfg/polybar/launch.sh"
            # Set keyboard layout
            if [ -n "${KB_VARIANT}" ]; then
                echo "exec_always --no-startup-id setxkbmap ${KB_LAYOUT} -variant ${KB_VARIANT}" >> "\$cfg/i3/config"
            else
                echo "exec_always --no-startup-id setxkbmap ${KB_LAYOUT}" >> "\$cfg/i3/config"
            fi
            ;;
        user_custom)
            mkdir -p "\$cfg/i3" "\$cfg/polybar" "\$cfg/picom" "\$cfg/dunst" "\$cfg/rofi" "\$cfg/kitty" "\$cfg/flameshot" "\$cfg/fastfetch" "\$cfg/scripts" "\$cfg/sounds"
            cp /root/wm-configs/i3/* "\$cfg/i3/"
            cp /root/wm-configs/polybar/* "\$cfg/polybar/"
            cp /root/wm-configs/picom/* "\$cfg/picom/"
            cp /root/wm-configs/dunst/* "\$cfg/dunst/"
            cp /root/wm-configs/rofi/* "\$cfg/rofi/"
            cp /root/wm-configs/kitty/* "\$cfg/kitty/"
            cp /root/wm-configs/flameshot/* "\$cfg/flameshot/"
            cp /root/wm-configs/fastfetch/* "\$cfg/fastfetch/"
            cp /root/wm-configs/scripts/* "\$cfg/scripts/"
            cp /root/wm-configs/sounds/* "\$cfg/sounds/"
            chmod +x "\$cfg/polybar/"*.sh "\$cfg/dunst/"*.sh "\$cfg/scripts/"*
            # Deploy screenlayout
            if [ -d /root/wm-configs/screenlayout ]; then
                mkdir -p "\$home/.screenlayout"
                cp /root/wm-configs/screenlayout/* "\$home/.screenlayout/"
                chmod +x "\$home/.screenlayout/"*.sh
            fi
            ;;
        sway)
            mkdir -p "\$cfg/sway" "\$cfg/waybar" "\$cfg/mako" "\$cfg/wofi" "\$cfg/foot"
            cp /root/wm-configs/config "\$cfg/sway/config"
            cp /root/wm-configs/waybar/* "\$cfg/waybar/"
            cp /root/wm-configs/mako/* "\$cfg/mako/"
            cp /root/wm-configs/wofi/* "\$cfg/wofi/"
            cp /root/wm-configs/foot/* "\$cfg/foot/"
            # Set keyboard layout
            sed -i 's/xkb_layout us/xkb_layout ${KB_LAYOUT}/' "\$cfg/sway/config"
            if [ -n "${KB_VARIANT}" ]; then
                sed -i '/xkb_layout ${KB_LAYOUT}/a\\    xkb_variant ${KB_VARIANT}' "\$cfg/sway/config"
            fi
            ;;
        hyprland)
            mkdir -p "\$cfg/hypr" "\$cfg/waybar" "\$cfg/wofi" "\$cfg/foot"
            cp /root/wm-configs/hyprland.conf "\$cfg/hypr/hyprland.conf"
            cp /root/wm-configs/waybar/* "\$cfg/waybar/"
            cp /root/wm-configs/wofi/* "\$cfg/wofi/"
            cp /root/wm-configs/foot/* "\$cfg/foot/"
            # Set keyboard layout
            sed -i 's/kb_layout = us/kb_layout = ${KB_LAYOUT}/' "\$cfg/hypr/hyprland.conf"
            if [ -n "${KB_VARIANT}" ]; then
                sed -i '/kb_layout = ${KB_LAYOUT}/a\\    kb_variant = ${KB_VARIANT}' "\$cfg/hypr/hyprland.conf"
            fi
            ;;
        kde)
            cp /root/wm-configs/kwinrc "\$cfg/kwinrc" 2>/dev/null || true
            cp /root/wm-configs/plasma-org.kde.plasma.desktop-appletsrc "\$cfg/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true
            ;;
    esac

    chown -R ${username}:${username} "\$home"
    rm -rf /root/wm-configs
    echo "Config templates deployed to \$cfg/"
fi

# Set X11 keyboard layout system-wide (localectl doesn't work in chroot)
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf << KBEOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "${KB_LAYOUT}"
KBEOF
if [ -n "${KB_VARIANT}" ]; then
    sed -i '/XkbLayout/a\\    Option "XkbVariant" "${KB_VARIANT}"' /etc/X11/xorg.conf.d/00-keyboard.conf
fi

# Enable eGPU service if deployed
if [ -f /etc/systemd/system/nvidia-egpu.service ]; then
    pacman -S --noconfirm --needed bolt
    systemctl enable bolt.service
    systemctl enable nvidia-egpu.service
    echo "eGPU auto-setup service enabled."
fi

# Create .xinitrc for X11-based WMs
case "${WM_CHOICE}" in
    i3|user_custom)
        cat > /home/${username}/.xinitrc << 'XINITEOF'
#!/bin/sh
[ -f ~/.Xresources ] && xrdb -merge ~/.Xresources
exec i3
XINITEOF
        chmod +x /home/${username}/.xinitrc
        chown ${username}:${username} /home/${username}/.xinitrc
        ;;
esac

# Auto-login on TTY1 and launch session
case "${WM_CHOICE}" in
    i3|user_custom|sway|hyprland)
        # Getty autologin on TTY1
        mkdir -p /etc/systemd/system/getty@tty1.service.d
        cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << GETTYEOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${username} --noclear %I \\\$TERM
GETTYEOF

        # Auto-launch session from .bash_profile
        case "${WM_CHOICE}" in
            i3|user_custom)
                cat >> /home/${username}/.bash_profile << 'AUTOXEOF'

# Auto-start i3
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
    exec startx
fi
AUTOXEOF
                ;;
            sway)
                cat >> /home/${username}/.bash_profile << 'AUTOXEOF'

# Auto-start Sway
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
    exec sway
fi
AUTOXEOF
                ;;
            hyprland)
                cat >> /home/${username}/.bash_profile << 'AUTOXEOF'

# Auto-start Hyprland
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
    exec Hyprland
fi
AUTOXEOF
                ;;
        esac
        chown ${username}:${username} /home/${username}/.bash_profile
        ;;
esac

# Install AUR helper
if [ "${AUR_HELPER}" != "none" ] && [ -n "${AUR_HELPER}" ]; then
    pacman -S --noconfirm --needed base-devel git
    cd /tmp
    sudo -u ${username} git clone https://aur.archlinux.org/${AUR_HELPER}.git
    cd ${AUR_HELPER}
    sudo -u ${username} makepkg -si --noconfirm || {
        echo "ERROR: AUR helper install failed. If a conflicting package exists, run:"
        echo "  pacman -Rns ${AUR_HELPER}-bin --noconfirm  (or vice versa)"
        echo "Then re-run the installer and resume."
    }
    cd /
    rm -rf /tmp/${AUR_HELPER}
    echo "AUR helper '${AUR_HELPER}' installed."
fi

# Install AUR browser if needed
if [ -n "${BROWSER_PKG}" ]; then
    case "${BROWSER_PKG}" in
        librewolf-bin|brave-bin)
            if command -v ${AUR_HELPER} &>/dev/null; then
                sudo -u ${username} ${AUR_HELPER} -S --noconfirm ${BROWSER_PKG}
            else
                echo "AUR helper not available. Install '${BROWSER_PKG}' manually after reboot."
            fi
            ;;
    esac
fi

echo "User ${username} created. ${session_hint}"
USEREOF

    chmod +x /mnt/root/user-setup.sh
    arch-chroot /mnt /usr/bin/bash /root/user-setup.sh
    rm -f /mnt/root/user-setup.sh
}

audit_boot_entries() {
    header "Boot Entry Audit"
    local entries_dir="/mnt/boot/loader/entries"
    if [ ! -d "$entries_dir" ]; then
        info "No boot entries directory found. Skipping audit."
        return
    fi

    # Collect all currently valid UUIDs (block devices)
    local -A valid_uuids=()
    while IFS= read -r uuid; do
        [ -n "$uuid" ] && valid_uuids["$uuid"]=1
    done < <(blkid -s UUID -o value 2>/dev/null)

    local -a stale_entries=()
    local -a stale_reasons=()

    for entry in "$entries_dir"/*.conf; do
        [ -f "$entry" ] || continue
        local entry_name
        entry_name=$(basename "$entry")
        local has_problem=false reason=""

        # Check UUIDs in options line
        while IFS= read -r line; do
            # Extract UUIDs from options (root=UUID=xxx or cryptdevice=UUID=xxx:name)
            for uuid in $(echo "$line" | grep -oP 'UUID=\K[a-fA-F0-9-]+'); do
                if [ -z "${valid_uuids[$uuid]+x}" ]; then
                    has_problem=true
                    reason="references unknown UUID=$uuid"
                    break
                fi
            done
            # Check PARTUUID too
            for puuid in $(echo "$line" | grep -oP 'PARTUUID=\K[a-fA-F0-9-]+'); do
                if ! blkid -t PARTUUID="$puuid" &>/dev/null; then
                    has_problem=true
                    reason="references unknown PARTUUID=$puuid"
                    break
                fi
            done
        done < <(grep -i '^options' "$entry")

        # Check if referenced kernel/initrd files exist
        for img in $(grep -iE '^(linux|initrd)' "$entry" | awk '{print $2}'); do
            if [ ! -f "/mnt/boot${img}" ] && [ ! -f "/mnt/boot/${img#/}" ]; then
                has_problem=true
                reason="${reason:+$reason; }missing file: $img"
            fi
        done

        if [ "$has_problem" = true ]; then
            stale_entries+=("$entry")
            stale_reasons+=("$reason")
        fi
    done

    if [ ${#stale_entries[@]} -eq 0 ]; then
        msg "All boot entries look valid."
        return
    fi

    warn "Found ${#stale_entries[@]} potentially stale boot entry/entries:"
    echo ""
    for i in "${!stale_entries[@]}"; do
        local ename
        ename=$(basename "${stale_entries[$i]}")
        local title
        title=$(grep -i '^title' "${stale_entries[$i]}" 2>/dev/null | head -1 | sed 's/^title[[:space:]]*//')
        echo -e "  ${RED}${ename}${NC}  (${title:-untitled})"
        echo -e "    Reason: ${stale_reasons[$i]}"
        echo ""
    done

    for i in "${!stale_entries[@]}"; do
        local ename
        ename=$(basename "${stale_entries[$i]}")
        warn "Entry '$ename' appears stale: ${stale_reasons[$i]}"
        echo -e "  ${YELLOW}Contents:${NC}"
        sed 's/^/    /' "${stale_entries[$i]}"
        echo ""
        if confirm "Delete stale entry '$ename'? (If unsure, keep it)"; then
            rm -f "${stale_entries[$i]}"
            msg "Deleted $ename"
        else
            info "Keeping $ename"
        fi
    done
}

# ============================================================
# PHASE 8: Final Verification & Reboot
# ============================================================
final_checks() {
    header "Final Verification"

    msg "Checking fstab..."
    if grep -q "$ROOT_PART\|$VG_NAME/root" /mnt/etc/fstab; then
        msg "fstab: root entry found."
    else
        warn "fstab: root entry may be missing! Check /mnt/etc/fstab"
    fi

    msg "Checking systemd-boot entries..."
    if [ -f /mnt/boot/loader/entries/arch.conf ]; then
        msg "Boot entry: arch.conf exists."
        cat /mnt/boot/loader/entries/arch.conf
    else
        err "Boot entry arch.conf is MISSING!"
    fi

    # Audit all boot entries for stale references
    audit_boot_entries

    msg "Checking mkinitcpio..."
    if [ -f /mnt/boot/initramfs-linux.img ]; then
        msg "initramfs-linux.img exists."
    else
        err "initramfs-linux.img is MISSING!"
    fi

    if [ "$PART_MODE" = "luks" ]; then
        info "LUKS mode: verify 'encrypt lvm2' hooks are in mkinitcpio.conf"
        grep "^HOOKS" /mnt/etc/mkinitcpio.conf
    elif [ "$PART_MODE" = "lvm" ]; then
        info "LVM mode: verify 'lvm2' hook is in mkinitcpio.conf"
        grep "^HOOKS" /mnt/etc/mkinitcpio.conf
    fi

    echo ""
    msg "Installation complete!"
}

do_reboot() {
    header "Ready to Reboot"
    warn "Remove the installation medium before rebooting."
    if confirm "Reboot now?"; then
        msg "Unmounting..."
        swapoff -a 2>/dev/null || true
        umount -R /mnt
        if [ "$PART_MODE" = "luks" ]; then
            vgchange -an "$VG_NAME" 2>/dev/null || true
            cryptsetup close "$LUKS_NAME" 2>/dev/null || true
        elif [ "$PART_MODE" = "lvm" ]; then
            vgchange -an "$VG_NAME" 2>/dev/null || true
        fi
        msg "Rebooting..."
        reboot
    else
        info "You can reboot manually when ready."
        info "Run: umount -R /mnt && reboot"
    fi
}

# ============================================================
# STATE SAVE / LOAD (for resume support)
# ============================================================
STATE_FILE="/tmp/arch-install-state.sh"

save_state() {
    local extra_names="" extra_sizes="" extra_mounts=""
    if [ "${#EXTRA_LV_NAMES[@]}" -gt 0 ] 2>/dev/null; then
        extra_names=$(printf '%q ' "${EXTRA_LV_NAMES[@]}")
        extra_sizes=$(printf '%q ' "${EXTRA_LV_SIZES[@]}")
        extra_mounts=$(printf '%q ' "${EXTRA_LV_MOUNTS[@]}")
    fi
    cat > "$STATE_FILE" << EOF
# Arch installer saved state — $(date)
DISK="$DISK"
PART_MODE="$PART_MODE"
EFI_PART="$EFI_PART"
EFI_REUSE=$EFI_REUSE
ROOT_PART="$ROOT_PART"
SWAP_PART="$SWAP_PART"
HOME_PART="$HOME_PART"
LUKS_PART="$LUKS_PART"
LUKS_NAME="$LUKS_NAME"
VG_NAME="$VG_NAME"
SWAP_SIZE="$SWAP_SIZE"
TIMEZONE="$TIMEZONE"
LOCALE="$LOCALE"
KEYMAP="$KEYMAP"
KB_LAYOUT="$KB_LAYOUT"
KB_VARIANT="$KB_VARIANT"
HOSTNAME_VAL="$HOSTNAME_VAL"
CPU_UCODE="$CPU_UCODE"
REUSE_EXISTING=$REUSE_EXISTING
WM_CHOICE="$WM_CHOICE"
AUR_HELPER="$AUR_HELPER"
BROWSER_PKG="$BROWSER_PKG"
EGPU_SETUP="$EGPU_SETUP"
EXTRA_LV_NAMES=($extra_names)
EXTRA_LV_SIZES=($extra_sizes)
EXTRA_LV_MOUNTS=($extra_mounts)
LAST_STEP="$1"
EOF
    msg "State saved (completed: $1)."
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        # shellcheck disable=SC1090
        source "$STATE_FILE"
        return 0
    fi
    return 1
}

resume_menu() {
    if ! [ -f "$STATE_FILE" ]; then
        return 1  # no saved state, start fresh
    fi

    # shellcheck disable=SC1090
    local saved_step
    saved_step=$(grep '^LAST_STEP=' "$STATE_FILE" | cut -d'"' -f2)

    echo ""
    info "Previous install session detected (completed through: ${BOLD}${saved_step}${NC})."
    info "Disk: $( grep '^DISK=' "$STATE_FILE" | cut -d'"' -f2 )  Mode: $( grep '^PART_MODE=' "$STATE_FILE" | cut -d'"' -f2 )"
    echo ""
    echo -e "  ${BOLD}1)${NC} Start fresh (ignore saved state)"
    echo -e "  ${BOLD}2)${NC} Resume from next step"
    echo ""

    local rc
    while true; do
        read -rp "Choose [1/2]: " rc
        case "$rc" in 1|2) break ;; *) echo "Invalid choice." ;; esac
    done

    if [ "$rc" = "2" ]; then
        load_state
        return 0  # 0 = resuming
    fi
    rm -f "$STATE_FILE"
    return 1  # 1 = start fresh
}

# ============================================================
# MAIN
# ============================================================

# Step definitions: name → function(s) to run
run_step() {
    case "$1" in
        uefi)        check_uefi ;;
        disks)       detect_disks; analyze_partitions ;;
        partitions)  select_partition_mode; handle_existing_disk
                     if [ "$REUSE_EXISTING" = false ]; then create_partitions; fi ;;
        format)      format_partitions; mount_partitions ;;
        wifi)        copy_wifi_config ;;
        base)        install_base ;;
        config)      gather_config; configure_system ;;
        bootloader)  setup_bootloader ;;
        packages)    install_packages ;;
        user)        setup_user_and_rice ;;
        finish)      final_checks; do_reboot ;;
    esac
}

readonly STEPS=(uefi disks partitions format wifi base config bootloader packages user finish)
readonly STEP_LABELS=(
    "UEFI check"
    "Disk detection & analysis"
    "Partitioning"
    "Format & mount"
    "WiFi config copy"
    "Base system install (pacstrap)"
    "System configuration (chroot)"
    "Bootloader setup"
    "WM selection & packages"
    "User account & config deploy"
    "Final checks & reboot"
)
readonly STEP_LABELS

main() {
    echo -e "${BOLD}${BLUE}"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║     Arch Linux Interactive Installer  ║"
    echo "  ║   Plain / LVM / LUKS + systemd-boot  ║"
    echo "  ╚══════════════════════════════════════╝"
    echo -e "${NC}"

    # Set keyboard layout for the live session
    info "Set your keyboard layout for this installer session?"
    info "Common: us (QWERTY), colemak, dvorak — or press Enter to keep default."
    local live_kb
    read -rp "Search keymaps [skip]: " live_kb
    if [ -n "$live_kb" ]; then
        local -a kb_matches
        mapfile -t kb_matches < <(localectl list-keymaps 2>/dev/null | grep -i "$live_kb")
        if [ ${#kb_matches[@]} -eq 0 ]; then
            warn "No keymaps matching '$live_kb'. Keeping default."
        elif [ ${#kb_matches[@]} -eq 1 ]; then
            loadkeys "${kb_matches[0]}" 2>/dev/null && msg "Loaded keymap: ${kb_matches[0]}" || warn "Failed to load keymap."
        else
            local j=1
            for km in "${kb_matches[@]}"; do
                echo "  $j) $km"
                j=$((j+1))
            done
            local kp
            read -rp "Pick [1-${#kb_matches[@]}]: " kp
            if [[ "$kp" =~ ^[0-9]+$ ]] && [ "$kp" -ge 1 ] && [ "$kp" -le "${#kb_matches[@]}" ]; then
                loadkeys "${kb_matches[$((kp-1))]}" 2>/dev/null && msg "Loaded keymap: ${kb_matches[$((kp-1))]}" || warn "Failed to load keymap."
            fi
        fi
    fi

    local start_idx=0

    if resume_menu; then
        # Find the step after LAST_STEP
        for i in "${!STEPS[@]}"; do
            if [ "${STEPS[$i]}" = "$LAST_STEP" ]; then
                start_idx=$((i + 1))
                break
            fi
        done
        if [ "$start_idx" -ge "${#STEPS[@]}" ]; then
            msg "All steps were already completed!"
            do_reboot
            return
        fi
        msg "Resuming from: ${STEP_LABELS[$start_idx]}"

        # Re-activate LUKS/LVM if needed for resume
        if [ "$start_idx" -gt 3 ]; then  # past format step
            if [ "$PART_MODE" = "luks" ] && [ -n "$LUKS_PART" ] && [ ! -e "/dev/mapper/$LUKS_NAME" ]; then
                warn "LUKS container needs to be reopened."
                cryptsetup open "$LUKS_PART" "$LUKS_NAME"
                vgchange -ay "$VG_NAME" 2>/dev/null || true
            elif [ "$PART_MODE" = "lvm" ]; then
                vgchange -ay "$VG_NAME" 2>/dev/null || true
            fi
            # Re-mount if needed
            if ! mountpoint -q /mnt 2>/dev/null; then
                mount "$ROOT_PART" /mnt 2>/dev/null || true
                [ -n "$HOME_PART" ] && mount --mkdir "$HOME_PART" /mnt/home 2>/dev/null || true
                for ei in "${!EXTRA_LV_NAMES[@]}"; do
                    mount --mkdir "/dev/$VG_NAME/${EXTRA_LV_NAMES[$ei]}" "/mnt${EXTRA_LV_MOUNTS[$ei]}" 2>/dev/null || true
                done
                mount --mkdir "$EFI_PART" /mnt/boot 2>/dev/null || true
                [ -n "$SWAP_PART" ] && swapon "$SWAP_PART" 2>/dev/null || true
            fi
        fi
    fi

    for _si in "${!STEPS[@]}"; do
        [ "$_si" -lt "$start_idx" ] && continue
        info "Step $((_si+1))/${#STEPS[@]}: ${STEP_LABELS[$_si]}"
        run_step "${STEPS[$_si]}"
        # Don't save state after the final step (reboot)
        if [ "${STEPS[$_si]}" != "finish" ]; then save_state "${STEPS[$_si]}"; fi
    done
}

main "$@"
