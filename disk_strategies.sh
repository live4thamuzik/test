#!/bin/bash
# disk_strategies.sh - Contains specific partitioning/storage layout functions

# --- Main Dispatcher for Disk Strategy ---
execute_disk_strategy() {
    log_info "Executing disk strategy: $PARTITION_SCHEME"
    
    local strategy_func=""
    local i=0
    # Iterate through the array to find the corresponding function name
    # We do this instead of direct string-based indexing, which fails in Bash 3.x
    while [ "$i" -lt "${#PARTITION_STRATEGY_FUNCTIONS[@]}" ]; do
        if [ "${PARTITION_STRATEGY_FUNCTIONS[$i]}" == "$PARTITION_SCHEME" ]; then
            strategy_func="${PARTITION_STRATEGY_FUNCTIONS[$((i+1))]}"
            break
        fi
        i=$((i+2))
    done

    if [[ -n "$strategy_func" ]]; then
        "$strategy_func" || error_exit "Disk strategy '$PARTITION_SCHEME' failed."
    else
        error_exit "Unknown partitioning scheme: $PARTITION_SCHEME."
    fi
    log_info "Disk strategy execution complete."
}

# --- Specific Partitioning Strategy Implementations ---

do_auto_simple_partitioning() {
    log_info "Starting auto simple partitioning for $INSTALL_DISK (Boot Mode: $BOOT_MODE)..."

    wipe_disk "$INSTALL_DISK"

    local current_start_mib=1 # Always start at 1MiB for the first partition
    local part_num=1 # Keep track of partition numbers
    local part_dev=""

    # Create partition table (GPT for UEFI, MBR for BIOS)
    if [ "$BOOT_MODE" == "uefi" ]; then
        parted -s "$INSTALL_DISK" mklabel gpt || error_exit "Failed to create GPT label on $INSTALL_DISK."
    else
        parted -s "$INSTALL_DISK" mklabel msdos || error_exit "Failed to create MBR label on $INSTALL_DISK."
    fi
    partprobe "$INSTALL_DISK"

    # EFI Partition (for UEFI)
    if [ "$BOOT_MODE" == "uefi" ]; then
        log_info "Creating EFI partition (${EFI_PART_SIZE_MIB}MiB)..."
        parted -s "$INSTALL_DISK" mkpart primary fat32 "${current_start_mib}MiB" "$((current_start_mib + EFI_PART_SIZE_MIB))MiB" set "$part_num" esp on || error_exit "Failed to create EFI partition."
        partprobe "$INSTALL_DISK"
        part_dev=$(get_partition_path "$INSTALL_DISK" "$part_num")
        format_filesystem "$part_dev" "vfat"
        capture_id_for_config "efi" "$part_dev" "UUID"
        capture_id_for_config "efi" "$part_dev" "PARTUUID"
        safe_mount "$part_dev" "/mnt/boot/efi"
        current_start_mib=$((current_start_mib + EFI_PART_SIZE_MIB))
        part_num=$((part_num + 1))
    fi

    # Swap Partition (if desired)
    if [ "$WANT_SWAP" == "yes" ]; then
        log_info "Creating Swap partition..."
        # Use an appropriate size for swap
        local swap_size_mib=$((2048)) # Defaulting to 2 GiB for a reasonable swap partition
        parted -s "$INSTALL_DISK" mkpart primary linux-swap "${current_start_mib}MiB" "$((current_start_mib + swap_size_mib))MiB" || error_exit "Failed to create swap partition."
        partprobe "$INSTALL_DISK"
        part_dev=$(get_partition_path "$INSTALL_DISK" "$part_num")
        format_filesystem "$part_dev" "swap"
        capture_id_for_config "swap" "$part_dev" "UUID"
        swapon "$part_dev" || error_exit "Failed to activate swap on $part_dev."
        current_start_mib=$((current_start_mib + swap_size_mib))
        part_num=$((part_num + 1))
    fi

    # Root Partition and Optional Home Partition
    local root_size_mib=$((102400)) # Defaulting to 100 GiB for a reasonable root partition

    if [ "$WANT_HOME_PARTITION" == "yes" ]; then
        log_info "Creating Root partition and separate Home partition (rest of disk)..."
        # Root partition (fixed size)
        parted -s "$INSTALL_DISK" mkpart primary "$ROOT_FILESYSTEM_TYPE" "${current_start_mib}MiB" "$((current_start_mib + root_size_mib))MiB" || error_exit "Failed to create root partition."
        partprobe "$INSTALL_DISK"
        part_dev=$(get_partition_path "$INSTALL_DISK" "$part_num")
        format_filesystem "$part_dev" "$ROOT_FILESYSTEM_TYPE"
        capture_id_for_config "root" "$part_dev" "UUID"
        safe_mount "$part_dev" "/mnt"
        current_start_mib=$((current_start_mib + root_size_mib))
        part_num=$((part_num + 1))

        # Home partition (takes remaining space)
        log_info "Creating Home partition (rest of disk)..."
        parted -s "$INSTALL_DISK" mkpart primary "$HOME_FILESYSTEM_TYPE" "${current_start_mib}MiB" "100%" || error_exit "Failed to create home partition."
        partprobe "$INSTALL_DISK"
        part_dev=$(get_partition_path "$INSTALL_DISK" "$part_num")
        format_filesystem "$part_dev" "$HOME_FILESYSTEM_TYPE"
        capture_id_for_config "home" "$part_dev" "UUID"
        mkdir -p /mnt/home || error_exit "Failed to create /mnt/home."
        safe_mount "$part_dev" "/mnt/home"
    else
        # Root takes all remaining space
        log_info "Creating Root partition (rest of disk)..."
        parted -s "$INSTALL_DISK" mkpart primary "$ROOT_FILESYSTEM_TYPE" "${current_start_mib}MiB" "100%" || error_exit "Failed to create root partition."
        partprobe "$INSTALL_DISK"
        part_dev=$(get_partition_path "$INSTALL_DISK" "$part_num")
        format_filesystem "$part_dev" "$ROOT_FILESYSTEM_TYPE"
        capture_id_for_config "root" "$part_dev" "UUID"
        safe_mount "$part_dev" "/mnt"
    fi

    log_info "Simple auto partitioning complete. Filesystems formatted and mounted."
}

do_auto_luks_lvm_partitioning() {
    log_info "Starting auto LUKS+LVM partitioning for $INSTALL_DISK (Boot Mode: $BOOT_MODE)..."

    wipe_disk "$INSTALL_DISK"

    local current_start_mib=1
    local part_num=1
    local part_dev=""

    # 1. Create partition table (GPT for UEFI, MBR for BIOS)
    if [ "$BOOT_MODE" == "uefi" ]; then
        parted -s "$INSTALL_DISK" mklabel gpt || error_exit "Failed to create GPT label on $INSTALL_DISK."
    else
        parted -s "$INSTALL_DISK" mklabel msdos || error_exit "Failed to create MBR label on $INSTALL_DISK."
    fi
    partprobe "$INSTALL_DISK"

    # 2. EFI Partition (for UEFI) - 1024MiB
    if [ "$BOOT_MODE" == "uefi" ]; then
        log_info "Creating EFI partition (${EFI_PART_SIZE_MIB}MiB)..."
        parted -s "$INSTALL_DISK" mkpart primary fat32 "${current_start_mib}MiB" "$((current_start_mib + EFI_PART_SIZE_MIB))MiB" set "$part_num" esp on || error_exit "Failed to create EFI partition."
        partprobe "$INSTALL_DISK"
        part_dev=$(get_partition_path "$INSTALL_DISK" "$part_num")
        format_filesystem "$part_dev" "vfat"
        capture_id_for_config "efi" "$part_dev" "UUID"
        capture_id_for_config "efi" "$part_dev" "PARTUUID"
        safe_mount "$part_dev" "/mnt/boot/efi"
        current_start_mib=$((current_start_mib + EFI_PART_SIZE_MIB))
        part_num=$((part_num + 1))
    fi

    # 3. Dedicated /boot Partition - 2GiB
    log_info "Creating dedicated /boot partition (${BOOT_PART_SIZE_MIB}MiB)..."
    parted -s "$INSTALL_DISK" mkpart primary ext4 "${current_start_mib}MiB" "$((current_start_mib + BOOT_PART_SIZE_MIB))MiB" || error_exit "Failed to create /boot partition."
    partprobe "$INSTALL_DISK"
    part_dev=$(get_partition_path "$INSTALL_DISK" "$part_num")
    format_filesystem "$part_dev" "ext4"
    capture_id_for_config "boot" "$part_dev" "UUID"
    mkdir -p /mnt/boot || error_exit "Failed to create /mnt/boot."
    safe_mount "$part_dev" "/mnt/boot"
    current_start_mib=$((current_start_mib + BOOT_PART_SIZE_MIB))
    part_num=$((part_num + 1))

    # 4. Main LUKS Container Partition (takes rest of disk)
    log_info "Creating LUKS container partition (rest of disk)..."
    parted -s "$INSTALL_DISK" mkpart primary ext4 "${current_start_mib}MiB" "100%" || error_exit "Failed to create LUKS container partition."
    partprobe "$INSTALL_DISK"
    part_dev=$(get_partition_path "$INSTALL_DISK" "$part_num")
    parted -s "$INSTALL_DISK" set "$part_num" lvm on || log_warn "Failed to set LVM flag on LUKS container partition."

    # Perform LUKS encryption on this partition
    local luks_name="lvm"
    encrypt_device "$part_dev" "$luks_name"

    # 5. Setup LVM on the encrypted device
    setup_lvm "/dev/mapper/$luks_name" "$VG_NAME"
    # LVs (lv_root, lv_swap, lv_home) are created, formatted, and mounted inside setup_lvm.

    log_info "LUKS+LVM partitioning complete. Filesystems formatted and mounted."
}

do_auto_raid_luks_lvm_partitioning() {
    log_info "Starting auto RAID+LUKS+LVM partitioning with disks: ${RAID_DEVICES[*]} (Boot Mode: $BOOT_MODE)..."

    if [ ${#RAID_DEVICES[@]} -lt 2 ]; then error_exit "RAID requires at least 2 disks."; fi

    local efi_part_num=1
    local boot_part_num=2
    local luks_part_num=3

    # --- Phase 1: Partition all RAID member disks identically ---
    for disk in "${RAID_DEVICES[@]}"; do
        log_info "Partitioning RAID member disk: $disk"
        wipe_disk "$disk"

        local current_start_mib=1

        parted -s "$disk" mklabel gpt || error_exit "Failed to create GPT label on $disk."
        partprobe "$disk"

        # 1. EFI partition on each disk (if UEFI)
        if [ "$BOOT_MODE" == "uefi" ]; then
            parted -s "$disk" mkpart primary fat32 "${current_start_mib}MiB" "$((current_start_mib + EFI_PART_SIZE_MIB))MiB" set "$efi_part_num" esp on || error_exit "Failed to create EFI partition on $disk."
            current_start_mib=$((current_start_mib + EFI_PART_SIZE_MIB))
        fi

        # 2. /boot partition on each disk (will be part of RAID1 for /boot)
        parted -s "$disk" mkpart primary ext4 "${current_start_mib}MiB" "$((current_start_mib + BOOT_PART_SIZE_MIB))MiB" || error_exit "Failed to create /boot partition on $disk."
        current_start_mib=$((current_start_mib + BOOT_PART_SIZE_MIB))
        
        # 3. Main LUKS Container Partition (takes rest of disk, will be part of RAID1 for LUKS)
        parted -s "$disk" mkpart primary ext4 "${current_start_mib}MiB" "100%" || error_exit "Failed to create LUKS container partition on $disk."
        parted -s "$disk" set "$luks_part_num" raid on || log_warn "Failed to set RAID flag on LUKS partition on $disk."
        partprobe "$disk"
    done

    # --- Phase 2: Assemble RAID Arrays ---
    # Create RAID1 for /boot
    local md_boot_dev="/dev/md0"
    local boot_component_devices=()
    for disk in "${RAID_DEVICES[@]}"; do
        boot_component_devices+=($(get_partition_path "$disk" "$boot_part_num"))
    done
    setup_raid "$RAID_LEVEL" "$md_boot_dev" "${boot_component_devices[@]}" || error_exit "RAID setup for /boot failed."
    format_filesystem "$md_boot_dev" "ext4"
    capture_id_for_config "boot" "$md_boot_dev" "UUID"
    mkdir -p /mnt/boot || error_exit "Failed to create /mnt/boot."
    safe_mount "$md_boot_dev" "/mnt/boot"


    # Create RAID1 for LUKS container
    local md_luks_container="/dev/md1"
    local luks_component_devices=()
    for disk in "${RAID_DEVICES[@]}"; do
        luks_component_devices+=($(get_partition_path "$disk" "$luks_part_num"))
    done
    setup_raid "$RAID_LEVEL" "$md_luks_container" "${luks_component_devices[@]}" || error_exit "RAID setup for LUKS container failed."


    # --- Phase 3: Encrypt the RAID device (md_luks_container) ---
    local luks_name="lvm"
    encrypt_device "$md_luks_container" "$luks_name"


    # --- Phase 4: Setup LVM on the encrypted RAID device ---
    setup_lvm "/dev/mapper/$luks_name" "$VG_NAME"


    # --- Phase 5: Mount EFI(s) for initial install ---
    # For UEFI, mount the EFI partition from the *first* RAID disk.
    if [ "$BOOT_MODE" == "uefi" ]; then
        local first_efi_dev=$(get_partition_path "${RAID_DEVICES[0]}" "$efi_part_num")
        format_filesystem "$first_efi_dev" "vfat"
        capture_id_for_config "efi" "$first_efi_dev" "UUID"
        capture_id_for_config "efi" "$first_efi_dev" "PARTUUID"
        mkdir -p /mnt/boot/efi || error_exit "Failed to create /mnt/boot/efi."
        safe_mount "$first_efi_dev" "/mnt/boot/efi"
    fi

    log_info "RAID+LUKS+LVM partitioning complete."
}

do_manual_partitioning_guided() {
    log_warn "You chose manual partitioning. The script will pause for you to set up partitions."
    log_warn "Please partition '$INSTALL_DISK' (and any other disks) using fdisk, parted, cryptsetup, mdadm, LVM tools."
    log_warn "You must create and mount the root filesystem at '/mnt'."
    log_warn "If using UEFI, create and mount the EFI System Partition at '/mnt/boot/efi'."
    log_warn "If using LVM, LUKS, or RAID, ensure they are opened/assembled before mounting."

    read -rp "Press Enter when you have finished manual partitioning and mounting to /mnt (and /mnt/boot/efi): "

    # Verify essential mounts
    if ! mountpoint -q /mnt; then
        error_exit "/mnt is not mounted. Please ensure your root partition is mounted correctly."
    fi
    if [ "$BOOT_MODE" == "uefi" ] && ! mountpoint -q /mnt/boot/efi; then
        log_warn "/mnt/boot/efi is not mounted. This is required for UEFI installations. Please mount it manually."
        read -rp "Press Enter to continue after mounting /mnt/boot/efi: "
        if ! mountpoint -q /mnt/boot/efi; then
            error_exit "/mnt/boot/efi is still not mounted. Cannot proceed with UEFI installation."
        fi
    fi

    log_info "Attempting to gather UUIDs from manually mounted partitions for fstab and bootloader..."
    local mounted_devs_info=$(findmnt -n --raw --output SOURCE,TARGET /mnt -R)

    # Process root
    local root_dev=$(echo "$mounted_devs_info" | awk '$2=="/mnt"{print $1}')
    if [ -n "$root_dev" ]; then
        capture_id_for_config "root" "$root_dev" "UUID"
        if [[ "$root_dev" =~ ^/dev/mapper/ ]]; then
            local lv_name=$(basename "$root_dev")
            local vg_name=$(basename "$(dirname "$root_dev")")
            LVM_DEVICES_MAP["${vg_name}_${lv_name}"]="$root_dev"
        fi
    else
        log_warn "Could not determine root device for UUID capture after manual partitioning."
    fi

    # Process EFI
    if [ "$BOOT_MODE" == "uefi" ]; then
        local efi_dev=$(echo "$mounted_devs_info" | awk '$2=="/mnt/boot/efi"{print $1}')
        if [ -n "$efi_dev" ]; then
            capture_id_for_config "efi" "$efi_dev" "UUID"
            capture_id_for_config "efi" "$efi_dev" "PARTUUID"
        else
            log_warn "Could not determine EFI device for UUID/PARTUUID capture after manual partitioning."
        fi
    fi

    # Process /boot (if separate)
    local boot_dev=$(echo "$mounted_devs_info" | awk '$2=="/mnt/boot" && $1!="/mnt"{print $1}')
    if [ -n "$boot_dev" ]; then
        capture_id_for_config "boot" "$boot_dev" "UUID"
    fi

    # Process /home (if separate)
    local home_dev=$(echo "$mounted_devs_info" | awk '$2=="/mnt/home"{print $1}')
    if [ -n "$home_dev" ]; then
        capture_id_for_config "home" "$home_dev" "UUID"
        if [[ "$home_dev" =~ ^/dev/mapper/ ]]; then
            local lv_name=$(basename "$home_dev")
            local vg_name=$(basename "$(dirname "$home_dev")")
            LVM_DEVICES_MAP["${vg_name}_${lv_name}"]="$home_dev"
        fi
    fi

    log_warn "Automatic LUKS/RAID/LVM detection for GRUB kernel parameters in manual mode is limited."
    log_warn "Please ensure your GRUB configuration (cryptdevice, rd.lvm.vg) is correct post-install if using complex setups."

    log_info "UUID capture for manual setup attempted. Please verify fstab and bootloader configs post-install."
}
