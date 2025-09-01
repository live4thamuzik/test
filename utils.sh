#!/bin/bash
# utils.sh - General helper functions for Archl4tm rewrite (Bash 3.x Compatible)

# ANSI escape codes for colors
readonly C_INFO='\e[32m'
readonly C_WARN='\e[33m'
readonly C_ERROR='\e[31m'
readonly C_HEADER='\e[36;1m'
readonly C_SUCCESS='\e[32;1m'
readonly C_RESET='\e[0m'

log_info() {
    echo -e "${C_INFO}[INFO]${C_RESET} $(date +%T) $*"
}

log_warn() {
    echo -e "${C_WARN}[WARN]${C_RESET} $(date +%T) $*" >&2
}

error_exit() {
    echo -e "${C_ERROR}[ERROR]${C_RESET} $(date +%T) $*" >&2
    exit 1
}

log_header() {
    echo -e "\n${C_HEADER}==================================================${C_RESET}"
    echo -e "${C_HEADER} $* ${C_RESET}"
    echo -e "${C_HEADER}==================================================${C_RESET}\n"
}

log_success() {
    echo -e "\n${C_SUCCESS}==================================================${C_RESET}"
    echo -e "${C_SUCCESS} $* ${C_RESET}"
    echo -e "${C_SUCCESS}==================================================${C_RESET}\n"
}

# --- System Checks ---
check_prerequisites() {
    log_info "Checking prerequisites..."
    if [ "$EUID" -ne 0 ]; then
        error_exit "This script must be run as root."
    fi

    log_info "Checking internet connection (pinging archlinux.org)..."
    if ! ping -c 1 -W 2 archlinux.org &>/dev/null; then
        error_exit "No active internet connection detected."
    fi
    log_info "Prerequisites met."
}

# --- Disk Utilities ---

# Returns "nvme" or "sd" or "unknown" based on device path.
get_device_type() {
    local dev_path="$1"
    # Bash 3.x compatible regex
    if echo "$dev_path" | grep -q "^/dev/nvme[0-9]\+n[0-9]\+$"; then
        echo "nvme"
    elif echo "$dev_path" | grep -q "^/dev/sd[a-z]\+$"; then
        echo "sd"
    else
        echo "unknown"
    fi
}

# Constructs the full partition path based on disk type.
# Args: $1 = base_disk (e.g., /dev/sda, /dev/nvme0n1), $2 = partition_number (e.g., 1, 2)
get_partition_path() {
    local base_disk="$1"
    local part_num="$2"
    local full_path=""

    local dev_type=$(get_device_type "$base_disk")
    if [ "$dev_type" == "nvme" ]; then
        full_path="${base_disk}p${part_num}"
    elif [ "$dev_type" == "sd" ]; then
        full_path="${base_disk}${part_num}"
    else
        error_exit "Unsupported disk type for partition path construction: $base_disk."
    fi
    echo "$full_path"
}

# Wipes a disk of signatures and partition tables.
# Args: $1 = disk_path (e.g., /dev/sda)
wipe_disk() {
    local disk_path="$1"
    log_info "Wiping existing data and signatures from $disk_path..."
    wipefs -af "$disk_path" &>/dev/null || log_warn "wipefs failed for $disk_path."

    if [ -b "$disk_path" ]; then
        sgdisk -Z "$disk_path" &>/dev/null || log_warn "sgdisk -Z failed for $disk_path."
        dd if=/dev/zero of="$disk_path" bs=512 count=1 conv=notrunc &>/dev/null || log_warn "dd zeroing MBR failed for $disk_path."
    else
        error_exit "Disk device $disk_path not found or not a block device."
    fi
    log_info "Disk $disk_path wiped."
}

# Formats a device with a specified filesystem.
# Args: $1 = dev_path, $2 = fs_type (e.g., "ext4", "vfat", "swap")
format_filesystem() {
    local dev_path="$1"
    local fs_type="$2"

    log_info "Formatting $dev_path as $fs_type..."
    case "$fs_type" in
        ext4)   mkfs.ext4 -F "$dev_path" || error_exit "Failed to format $dev_path as ext4.";;
        xfs)    mkfs.xfs -f "$dev_path" || error_exit "Failed to format $dev_path as xfs.";;
        btrfs)  mkfs.btrfs -f "$dev_path" || error_exit "Failed to format $dev_path as btrfs.";;
        vfat)   mkfs.vfat -F 32 "$dev_path" || error_exit "Failed to format $dev_path as vfat.";;
        swap)   mkswap "$dev_path" || error_exit "Failed to create swap on $dev_path.";;
        *)      error_exit "Unsupported filesystem type for formatting: $fs_type.";;
    esac
    log_info "$dev_path formatted as $fs_type."
}

# Safely mounts a device to a mount point.
# Args: $1 = device_path, $2 = mount_point
safe_mount() {
    local dev="$1"
    local mnt="$2"
    mkdir -p "$mnt" || error_exit "Failed to create mount point $mnt."
    log_info "Mounting $dev to $mnt..."
    mount "$dev" "$mnt" || error_exit "Failed to mount $dev to $mnt."
}

# Safely unmounts a path. Uses lazy unmount first.
# Args: $1 = mount_point
safe_umount() {
    local mnt="$1"
    if mountpoint -q "$mnt"; then
        log_info "Attempting lazy unmount for $mnt..."
        umount -l "$mnt" &>/dev/null || true
        if mountpoint -q "$mnt"; then
            log_info "Attempting forceful unmount for $mnt..."
            umount "$mnt" &>/dev/null || log_warn "Failed to unmount $mnt."
        fi
    fi
}

# Captures UUID or PARTUUID of a device and stores it in global variables (no associative array for Bash 3.x).
# Args: $1 = key_prefix (e.g., "root", "efi"), $2 = dev_path, $3 = id_type ("UUID" or "PARTUUID")
capture_id_for_config() {
    local key_prefix="$1" # e.g., "efi", "root", "luks_container", "lv_root"
    local dev_path="$2"   # e.g., /dev/sda1, /dev/mapper/cryptroot
    local id_type="$3"    # "UUID" or "PARTUUID"

    if [ ! -b "$dev_path" ]; then
        error_exit "Device $dev_path not found or not a block device for ${id_type} capture."
    fi

    log_info "Capturing ${id_type} for ${key_prefix} from ${dev_path}..."
    local id_value=$(blkid -s "$id_type" -o value "$dev_path")
    if [ -z "$id_value" ]; then
        error_exit "Could not retrieve ${id_type} for ${dev_path}. Check device formatting or type."
    fi
    # Use explicit variable names for Bash 3.x (no declare -A PARTITION_UUIDS)
    case "${key_prefix}_${id_type}" in
        efi_UUID) PARTITION_UUIDS_EFI_UUID="$id_value";;
        efi_PARTUUID) PARTITION_UUIDS_EFI_PARTUUID="$id_value";;
        root_UUID) PARTITION_UUIDS_ROOT_UUID="$id_value";;
        boot_UUID) PARTITION_UUIDS_BOOT_UUID="$id_value";;
        swap_UUID) PARTITION_UUIDS_SWAP_UUID="$id_value";;
        home_UUID) PARTITION_UUIDS_HOME_UUID="$id_value";;
        luks_container_UUID) PARTITION_UUIDS_LUKS_CONTAINER_UUID="$id_value";;
        lv_root_UUID) PARTITION_UUIDS_LV_ROOT_UUID="$id_value";;
        lv_swap_UUID) PARTITION_UUIDS_LV_SWAP_UUID="$id_value";;
        lv_home_UUID) PARTITION_UUIDS_LV_HOME_UUID="$id_value";;
        *) log_warn "Attempted to capture unknown UUID/PARTUUID for key_prefix=$key_prefix, id_type=$id_type.";;
    esac
    log_info "Captured ${id_type} for ${key_prefix}: ${id_value}"
}

# Gets the UUID of an opened LUKS device.
# Args: $1 = luks_dev_mapper_path (e.g., /dev/mapper/cryptroot)
get_luks_uuid() {
    local luks_mapper_path="$1"
    local luks_uuid=$(blkid -s UUID -o value "$luks_mapper_path")
    if [ -z "$luks_uuid" ]; then
        error_exit "Could not get UUID for opened LUKS device: $luks_mapper_path."
    fi
    echo "$luks_uuid"
}

# Gets the full path to an LVM Logical Volume.
# Args: $1 = volume_group_name, $2 = logical_volume_name
get_lvm_lv_path() {
    local vg_name="$1"
    local lv_name="$2"
    local lv_path=""

    if [ -b "/dev/mapper/${vg_name}-${lv_name}" ]; then
        lv_path="/dev/mapper/${vg_name}-${lv_name}"
    elif [ -b "/dev/${vg_name}/${lv_name}" ]; then
        lv_path="/dev/${vg_name}/${lv_name}"
    else
        error_exit "Logical Volume ${vg_name}/${lv_name} not found."
    fi
    echo "$lv_path"
}


# --- Complex Storage Operations ---

# Encrypts a device with LUKS.
# Args: $1 = dev_path (e.g., /dev/sda2), $2 = luks_name (e.g., cryptroot)
# Global: LUKS_PASSPHRASE (read from config.sh)
# Global: LUKS_CRYPTROOT_DEV (Bash 3.x way to store opened device path)
encrypt_device() {
    local dev_path="$1"
    local luks_name="$2"
    log_info "Encrypting $dev_path with LUKS as $luks_name..."
    echo -n "$LUKS_PASSPHRASE" | cryptsetup luksFormat --type luks2 --cipher "aes-xts-plain64" --key-size "512" --hash "sha512" "$dev_path" -d - \
        --verbose --verify-passphrase || error_exit "LUKS format failed for $dev_path."
    
    # Open the LUKS device
    echo -n "$LUKS_PASSPHRASE" | cryptsetup open "$dev_path" "$luks_name" -d - || error_exit "LUKS open failed for $dev_path."
    
    capture_id_for_config "luks_container" "$dev_path" "UUID"
    LUKS_CRYPTROOT_DEV="/dev/mapper/$luks_name" # Store opened path in global scalar var for Bash 3.x
    log_info "$dev_path encrypted and opened as /dev/mapper/$luks_name."
}

# Sets up LVM Physical Volume, Volume Group, and Logical Volumes.
# Args: $1 = pv_dev (e.g., /dev/mapper/cryptroot), $2 = vg_name (e.g., volgroup0)
# Global: LV_LAYOUT_LV_ROOT, LV_LAYOUT_LV_SWAP, LV_LAYOUT_LV_HOME (from config.sh)
# Global: DEFAULT_LV_MOUNTPOINTS_LV_ROOT, DEFAULT_LV_MOUNTPOINTS_LV_SWAP, DEFAULT_LV_MOUNTPOINTS_LV_HOME (from config.sh)
# Global: DEFAULT_LV_FSTYPES_LV_ROOT, DEFAULT_LV_FSTYPES_LV_SWAP, DEFAULT_LV_FSTYPES_LV_HOME (from config.sh)
# Global: WANT_SWAP, WANT_HOME_PARTITION (from config.sh, user choices)
# Global: LV_ROOT_PATH, LV_SWAP_PATH, LV_HOME_PATH (Bash 3.x way to store LV paths)
setup_lvm() {
    local pv_dev="$1"
    local vg_name="$2"
    log_info "Setting up LVM on $pv_dev in Volume Group $vg_name..."

    pvcreate -y "$pv_dev" || error_exit "pvcreate failed for $pv_dev."
    vgcreate "$vg_name" "$pv_dev" || error_exit "vgcreate failed for $vg_name."

    # Root LV
    local lv_name="lv_root"
    local lv_size="${LV_LAYOUT_LV_ROOT}"
    local lv_mnt_point="${DEFAULT_LV_MOUNTPOINTS_LV_ROOT}"
    local lv_fs_type="${DEFAULT_LV_FSTYPES_LV_ROOT}"
    local lv_path=""

    log_info "Creating Logical Volume $lv_name ($lv_size) in VG $vg_name..."
    if echo "$lv_size" | grep -q '%'; then
        lvcreate -l "$lv_size" "$vg_name" -n "$lv_name" || error_exit "lvcreate failed for $lv_name."
    else
        lvcreate -L "$lv_size" "$vg_name" -n "$lv_name" || error_exit "lvcreate failed for $lv_name."
    fi

    # Check for the existence of the LV device file
    log_info "Waiting for logical volume device to appear..."
    local check_path=""
    for i in $(seq 1 10); do
        check_path=$(get_lvm_lv_path "$vg_name" "$lv_name")
        if [ -b "$check_path" ]; then
            lv_path="$check_path"
            break
        fi
        sleep 0.5
    done

    if [ -z "$lv_path" ]; then
        error_exit "Logical volume device file for $lv_name did not appear."
    fi

    LV_ROOT_PATH="$lv_path" # Assign to global variable
    
    format_filesystem "$lv_path" "$lv_fs_type"
    capture_id_for_config "$lv_name" "$lv_path" "UUID"
    safe_mount "$lv_path" "$lv_mnt_point"


    # Swap LV (if desired)
    if [ "$WANT_SWAP" == "yes" ]; then
        lv_name="lv_swap"
        lv_size="${LV_LAYOUT_LV_SWAP}"
        
        log_info "Creating Logical Volume $lv_name ($lv_size) in VG $vg_name..."
        if echo "$lv_size" | grep -q '%'; then
            lvcreate -l "$lv_size" "$vg_name" -n "$lv_name" || error_exit "lvcreate failed for $lv_name."
        else
            lvcreate -L "$lv_size" "$vg_name" -n "$lv_name" || error_exit "lvcreate failed for $lv_name."
        fi
        
        # Check for the existence of the LV device file
        local swap_path=""
        for i in $(seq 1 10); do
            swap_path=$(get_lvm_lv_path "$vg_name" "$lv_name")
            if [ -b "$swap_path" ]; then
                break
            fi
            sleep 0.5
        done
        if [ -z "$swap_path" ]; then
            error_exit "Logical volume device file for $lv_name did not appear."
        fi

        LV_SWAP_PATH="$swap_path" # Assign to global variable
        lv_fs_type="${DEFAULT_LV_FSTYPES_LV_SWAP}"
        
        format_filesystem "$swap_path" "$lv_fs_type"
        capture_id_for_config "$lv_name" "$swap_path" "UUID"
        swapon "$swap_path" || error_exit "Failed to activate swap LV: $swap_path."
    fi

    # Home LV (if desired)
    if [ "$WANT_HOME_PARTITION" == "yes" ]; then
        lv_name="lv_home"
        lv_size="${LV_LAYOUT_LV_HOME}"
        
        log_info "Creating Logical Volume $lv_name ($lv_size) in VG $vg_name..."
        if echo "$lv_size" | grep -q '%'; then
            lvcreate -l "$lv_size" "$vg_name" -n "$lv_name" || error_exit "lvcreate failed for $lv_name."
        else
            lvcreate -L "$lv_size" "$vg_name" -n "$lv_name" || error_exit "lvcreate failed for $lv_name."
        fi

        # Check for the existence of the LV device file
        local home_path=""
        for i in $(seq 1 10); do
            home_path=$(get_lvm_lv_path "$vg_name" "$lv_name")
            if [ -b "$home_path" ]; then
                break
            fi
            sleep 0.5
        done
        if [ -z "$home_path" ]; then
            error_exit "Logical volume device file for $lv_name did not appear."
        fi

        LV_HOME_PATH="$home_path" # Assign to global variable
        lv_mnt_point="${DEFAULT_LV_MOUNTPOINTS_LV_HOME}"
        lv_fs_type="${DEFAULT_LV_FSTYPES_LV_HOME}"
        
        format_filesystem "$home_path" "$lv_fs_type"
        capture_id_for_config "$lv_name" "$home_path" "UUID"
        safe_mount "$home_path" "$lv_mnt_point"
    fi

    log_info "LVM setup complete for $vg_name."
}

# Sets up a software RAID array.
# Args: $1 = raid_level, $2 = md_name (e.g., md0), $3... = component_devices (e.g., /dev/sdb1 /dev/sdc1)
setup_raid() {
    local raid_level="$1"
    local md_name="$2"
    shift 2
    local component_devices=("$@")

    log_info "Setting up RAID$raid_level for $md_name with devices: ${component_devices[*]}..."
    mdadm --create "$md_name" --level="$raid_level" --raid-devices="${#component_devices[@]}" "${component_devices[@]}" --force || error_exit "mdadm create failed for $md_name."
    
    # Do NOT save mdadm.conf here. That happens in chroot_config.sh
    log_info "RAID setup complete for $md_name."
}


# --- Pacman / Package Management Wrappers ---

# Installs prerequisite packages on the live ISO.
install_reflector_prereqs_live() {
    log_info "Installing prerequisite packages on Live ISO (pacman-contrib, reflector, rsync)..."
    pacman -Sy --noconfirm --needed pacman-contrib reflector rsync || error_exit "Failed to install prerequisite packages on Live ISO."
    log_info "Prerequisite packages installed."
}

# Configures pacman mirrorlist using reflector on the live ISO.
# Args: $1 = country code (e.g., "US", "DE")
configure_mirrors_live() {
    local country_code="$1"
    log_info "Configuring pacman mirrors for faster downloads using reflector for country: $country_code..."
    local mirrorlist_path="/etc/pacman.d/mirrorlist"

    if [ -f "$mirrorlist_path" ]; then
        log_info "Backing up current mirrorlist."
        cp "$mirrorlist_path" "${mirrorlist_path}.backup" || log_warn "Failed to backup mirrorlist."
    fi

    log_info "Running reflector to generate new mirrorlist..."
    reflector -c "$country_code" -a 72 -f 10 -l 10 --sort rate --save "$mirrorlist_path" || error_exit "Reflector failed to update mirrorlist."
    log_info "Pacman mirrorlist configured successfully."
}

# Runs pacstrap to install the base system into /mnt.
# Global: KERNEL_TYPE (e.g., "linux", "linux-lts")
run_pacstrap_base_install() {
    log_info "Running pacstrap to install base system with ${KERNEL_TYPE} kernel..."

    local kernel_packages=""
    if [ "$KERNEL_TYPE" == "linux" ]; then
        kernel_packages="linux linux-firmware linux-headers"
    elif [ "$KERNEL_TYPE" == "linux-lts" ]; then
        kernel_packages="linux-lts linux-lts-headers"
    else
        error_exit "Unsupported KERNEL_TYPE: $KERNEL_TYPE."
    fi

    # Pass all arguments passed to run_pacstrap_base_install directly to pacstrap
    # This expects arguments to be individual package names.
    pacstrap -K /mnt "$@" --noconfirm --needed || error_exit "Pacstrap failed to install base system."

    log_info "Pacstrap base system complete."
}

# Installs packages inside the chroot environment.
# Args: $@ = packages to install (e.g., "plasma sddm")
install_packages_chroot() {
    local packages="$@"
    log_info "Installing packages inside chroot: '$packages'..."
    pacman -S --noconfirm --needed $packages || error_exit "Failed to install packages inside chroot: '$packages'."
    log_info "Packages installed inside chroot: '$packages'."
}

# Updates the entire system inside the chroot.
update_system_chroot() {
    log_info "Updating entire system inside chroot..."
    pacman -Syu --noconfirm || error_exit "Failed to update system inside chroot."
    log_info "System updated inside chroot."
}

# Installs CPU microcode packages inside the chroot.
# Global: CPU_MICROCODE_TYPE (e.g., "intel", "amd")
install_microcode_chroot() {
    local microcode_package=""
    if [ "$CPU_MICROCODE_TYPE" == "intel" ]; then
        microcode_package="intel-ucode"
    elif [ "$CPU_MICROCODE_TYPE" == "amd" ]; then
        microcode_package="amd-ucode"
    else
        log_info "No specific CPU microcode type detected or needed. Skipping."
        return 0
    fi

    log_info "Installing $microcode_package inside chroot..."
    pacman -Sy --noconfirm --needed "$microcode_package" || error_exit "Failed to install $microcode_package inside chroot."
    log_info "$microcode_package installed."
}


# --- File System / Chroot Configuration Utilities ---

# Generates /etc/fstab using UUIDs.
generate_fstab() {
    log_info "Generating fstab using UUIDs..."
    genfstab -U /mnt > /mnt/etc/fstab || error_exit "Failed to generate fstab."
    log_info "fstab generated successfully at /mnt/etc/fstab."
}

# Edits a file inside the chroot using sed.
# Args: $1 = file_path_in_chroot, $2 = sed_expression
edit_file_in_chroot() {
    local file_path="$1"
    local sed_expr="$2"
    log_info "Editing $file_path inside chroot with sed: '$sed_expr'"
    
    # Create a backup before editing
    cp "$file_path" "${file_path}.bak" || log_warn "Failed to create backup of $file_path."

    sed -i "$sed_expr" "$file_path" || error_exit "Failed to edit $file_path inside chroot."
    log_info "File $file_path modified."
}

# Enables a systemd service inside the chroot.
# Args: $1 = service_name (e.g., "NetworkManager.service", "gdm")
enable_systemd_service_chroot() {
    local service_name="$1"
    log_info "Enabling systemd service $service_name inside chroot..."
    systemctl enable "$service_name" || error_exit "Failed to enable service $service_name inside chroot."
    log_info "Service $service_name enabled."
}

# --- Security / Credential Handling ---

# Prompts user for a password securely and validates minimum length.
# Args: $1 = prompt_message, $2 = name_of_variable_to_store_password (string)
secure_password_input() {
    local prompt_msg="$1"
    local result_var_name="$2" # This is now the string name of the result variable

    while true; do
        read -rsp "$prompt_msg (min 8 chars): " "$result_var_name" # Direct expansion here
        echo
        if [ -n "${!result_var_name}" ] && [ ${#result_var_name} -ge 8 ]; then # Check length of expanded value
            break
        else
            log_warn "Password too short or empty. Please enter at least 8 characters."
        fi
    done
}

# --- General Utility / String Manipulation ---

# Trims leading/trailing whitespace from a string.
trim_string() {
    local s="$1"
    echo "$s" | xargs
}

# Saves the current configuration variables to a file.
# Args: $1 = output_file_path
# Global: All config.sh variables populated by dialogs.
save_current_config() {
    local output_file="$1"
    log_info "Saving current installation configuration to $output_file (excluding passwords)."

    {
        echo "#!/bin/bash"
        echo "# Archl4tm User Configuration - Generated on $(date)"
        echo "# This file can be sourced by install_arch.sh to load previous choices."
        echo "# Edit it to pre-configure future installations."
        echo ""

        # List all simple variables that are populated by dialogs
        local vars_to_save=(
            "INSTALL_DISK" "BOOT_MODE" "OVERRIDE_BOOT_MODE" "WANT_WIFI_CONNECTION"
            "PARTITION_SCHEME" "WANT_SWAP" "WANT_HOME_PARTITION" "WANT_ENCRYPTION"
            "WANT_LVM" "WANT_RAID" "RAID_LEVEL" "KERNEL_TYPE" "CPU_MICROCODE_TYPE"
            "TIMEZONE" "LOCALE" "KEYMAP" "REFLECTOR_COUNTRY_CODE" "SYSTEM_HOSTNAME"
            "DESKTOP_ENVIRONMENT" "DISPLAY_MANAGER" "GPU_DRIVER_TYPE" "BOOTLOADER_TYPE"
            "ENABLE_OS_PROBER" "WANT_MULTILIB" "WANT_AUR_HELPER" "AUR_HELPER_CHOICE"
            "WANT_FLATPAK" "INSTALL_CUSTOM_PACKAGES" "INSTALL_CUSTOM_AUR_PACKAGES"
            "WANT_GRUB_THEME" "GRUB_THEME_CHOICE" "WANT_NUMLOCK_ON_BOOT"
        )

        for var_name in "${vars_to_save[@]}"; do
            # Check if the variable exists and is a simple variable (Bash 3.x compat)
            # Use indirect expansion for checking variable existence
            if eval "test -n \"\${$var_name+defined}\""; then # Check if var is set
                # Ensure it's not an array, as declare -a for arrays is different from scalars
                # Bash 3.x doesn't have declare -p for types robustly. This check will be simplified.
                local is_array=0
                # Crude check for Bash 3.x - assume simple variables unless explicitly managed
                # If we rely on specific array checks, Bash 3.x won't work well here for declare -a.
                # For `save_current_config`, we just dump what we know are scalar and RAID_DEVICES (explicitly handled).
                
                # Check if it's RAID_DEVICES, which is an array
                if [ "$var_name" == "RAID_DEVICES" ]; then
                    is_array=1
                fi

                if [ "$is_array" -eq 0 ]; then
                    printf '%s="%s"\n' "$var_name" "$(printf %s "${!var_name}" | sed 's/"/\\"/g')"
                fi
            fi
        done
        
        # Specifically save RAID_DEVICES array if it's populated (Bash 3.x explicit array dump)
        if [ ${#RAID_DEVICES[@]} -gt 0 ]; then
            echo ""
            echo "declare -a RAID_DEVICES=("
            for element in "${RAID_DEVICES[@]}"; do
                printf '    "%s"\n' "$(printf %s "$element" | sed 's/"/\\"/g')"
            done
            echo ")"
        fi

        echo ""
        echo "# NOTE: Passwords (ROOT_PASSWORD, MAIN_USER_PASSWORD, LUKS_PASSPHRASE) are NOT saved here for security reasons."
        echo "#       You will be prompted for them during script execution."

    } > "$output_file" || error_exit "Failed to save configuration to $output_file."
    
    chmod 600 "$output_file"
    log_info "Configuration saved successfully to $output_file."
}

run_in_chroot() {
    log_info "Executing chroot script"
    arch-chroot /mnt /bin/bash -c ./chroot-config.sh || error_exit "Chroot script execution failed: ${script_to_run}"
    
    log_info "Chroot script executed successfully."
    return 0
}

# --- Final Cleanup Function ---
final_cleanup() {
    log_info "Unmounting all filesystems under /mnt..."
    # The -R flag recursively unmounts all filesystems rooted at the specified directory.
    # The script will exit if this command fails due to 'set -e'.
    umount -R /mnt
    log_success "All temporary filesystems unmounted successfully."
}
