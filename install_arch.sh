#!/bin/bash
# install_arch.sh - Arch Linux Automated Installer

# Strict mode: Exit on error, unset variables, pipefail
set -euo pipefail

# --- Source all necessary script files ---
# Source config.sh first to get default variables and arrays/maps
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/dialogs.sh"
source "$(dirname "${BASH_SOURCE[0]}")/disk_strategies.sh"

# --- Main Installation Function ---
main() {
    log_header "ARCHL4TM: Tasteful Arch Linux Installation"

    check_prerequisites || error_exit "Prerequisite check failed."

    # Install reflector prerequisites and configure mirrors (always on Live ISO)
    install_reflector_prereqs_live || error_exit "Live ISO prerequisites failed."
    configure_mirrors_live "$REFLECTOR_COUNTRY_CODE" || error_exit "Mirror configuration failed."

    # Stage 1: Gather User Input (Always interactive now, no config loading)
    log_header "Stage 1: Gathering Installation Details"
    gather_installation_details || error_exit "Installation details gathering failed."
    display_summary_and_confirm || error_exit "Installation cancelled by user."

    # Stage 2: Disk Partitioning and Formatting
    log_header "Stage 2: Disk Partitioning and Formatting"
    execute_disk_strategy || error_exit "Disk partitioning and formatting failed."

    # Stage 3: Base System Installation
    log_header "Stage 3: Installing Base System"
    install_base_system_target || error_exit "Base system installation failed."

    # Stage 4: Chroot Configuration
    log_header "Stage 4: Post-Installation (Chroot) Configuration"
    # Copy essential script files into /mnt for chroot execution
    log_info "Copying chroot configuration files to /mnt..."
    local script_root_dir="$(dirname "${BASH_SOURCE[0]}")"
    local chroot_target_dir="/archl4tm"
    local install_script_path_in_chroot="/mnt/$chroot_target_dir"

    mkdir -p "$install_script_path_in_chroot" || error_exit "Failed to create target directory '$install_script_path_in_chroot'."
    
    # Copy chroot_config.sh
    if [ ! -f "$script_root_dir/chroot_config.sh" ]; then
        error_exit "Source file not found: $script_root_dir/chroot_config.sh. Cannot proceed."
    fi
    log_info "Attempting to copy $script_root_dir/chroot_config.sh..."
    cp "$script_root_dir/chroot_config.sh" "$install_script_path_in_chroot/" || error_exit "Failed to copy chroot_config.sh."
    if [ ! -f "$install_script_path_in_chroot/chroot_config.sh" ]; then
        error_exit "Destination file NOT FOUND after copying: $install_script_path_in_chroot/chroot_config.sh."
    fi

    # Copy config.sh
    if [ ! -f "$script_root_dir/config.sh" ]; then
        error_exit "Source file not found: $script_root_dir/config.sh. Cannot proceed."
    fi
    log_info "Attempting to copy $script_root_dir/config.sh..."
    cp "$script_root_dir/config.sh" "$install_script_path_in_chroot/" || error_exit "Failed to copy config.sh to chroot."
    if [ ! -f "$install_script_path_in_chroot/config.sh" ]; then
        error_exit "Destination file NOT FOUND after copying: $install_script_path_in_chroot/config.sh."
    fi

    # Copy utils.sh
    if [ ! -f "$script_root_dir/utils.sh" ]; then
        error_exit "Source file not found: $script_root_dir/utils.sh. Cannot proceed."
    fi
    log_info "Attempting to copy $script_root_dir/utils.sh..."
    cp "$script_root_dir/utils.sh" "$install_script_path_in_chroot/" || error_exit "Failed to copy utils.sh to chroot."
    if [ ! -f "$install_script_path_in_chroot/utils.sh" ]; then
        error_exit "Destination file NOT FOUND after copying: $install_script_path_in_chroot/utils.sh."
    fi
    
    log_info "Setting permissions for chroot scripts..."
    arch-chroot /mnt chmod +x "$chroot_target_dir/chroot_config.sh" || error_exit "Failed to make chroot script executable."
    arch-chroot /mnt chmod +x "$chroot_target_dir/config.sh" || error_exit "Failed to make chroot config executable."
    arch-chroot /mnt chmod +x "$chroot_target_dir/utils.sh" || error_exit "Failed to make chroot utils executable."

    log_info "Executing chroot configuration script inside chroot..."
    
    # Use 'env' to explicitly pass the variables to the chroot session
    env INSTALL_DISK="$INSTALL_DISK" \
    BOOT_MODE="$BOOT_MODE" \
    WANT_ENCRYPTION="$WANT_ENCRYPTION" \
    LUKS_PASSPHRASE="$LUKS_PASSPHRASE" \
    VG_NAME="$VG_NAME" \
    WANT_LVM="$WANT_LVM" \
    WANT_RAID="$WANT_RAID" \
    RAID_LEVEL="$RAID_LEVEL" \
    KERNEL_TYPE="$KERNEL_TYPE" \
    CPU_MICROCODE_TYPE="$CPU_MICROCODE_TYPE" \
    TIMEZONE="$TIMEZONE" \
    LOCALE="$LOCALE" \
    KEYMAP="$KEYMAP" \
    REFLECTOR_COUNTRY_CODE="$REFLECTOR_COUNTRY_CODE" \
    SYSTEM_HOSTNAME="$SYSTEM_HOSTNAME" \
    ROOT_PASSWORD="$ROOT_PASSWORD" \
    MAIN_USERNAME="$MAIN_USERNAME" \
    MAIN_USER_PASSWORD="$MAIN_USER_PASSWORD" \
    DESKTOP_ENVIRONMENT="$DESKTOP_ENVIRONMENT" \
    DISPLAY_MANAGER="$DISPLAY_MANAGER" \
    GPU_DRIVER_TYPE="$GPU_DRIVER_TYPE" \
    BOOTLOADER_TYPE="$BOOTLOADER_TYPE" \
    ENABLE_OS_PROBER="$ENABLE_OS_PROBER" \
    WANT_MULTILIB="$WANT_MULTILIB" \
    WANT_AUR_HELPER="$WANT_AUR_HELPER" \
    AUR_HELPER_CHOICE="$AUR_HELPER_CHOICE" \
    WANT_FLATPAK="$WANT_FLATPAK" \
    INSTALL_CUSTOM_PACKAGES="$INSTALL_CUSTOM_PACKAGES" \
    CUSTOM_PACKAGES="$CUSTOM_PACKAGES" \
    INSTALL_CUSTOM_AUR_PACKAGES="$INSTALL_CUSTOM_AUR_PACKAGES" \
    CUSTOM_AUR_PACKAGES="$CUSTOM_AUR_PACKAGES" \
    WANT_GRUB_THEME="$WANT_GRUB_THEME" \
    GRUB_THEME_CHOICE="$GRUB_THEME_CHOICE" \
    WANT_NUMLOCK_ON_BOOT="$WANT_NUMLOCK_ON_BOOT" \
    WANT_DOTFILES_DEPLOYMENT="$WANT_DOTFILES_DEPLOYMENT" \
    DOTFILES_REPO_URL="$DOTFILES_REPO_URL" \
    DOTFILES_BRANCH="$DOTFILES_BRANCH" \
    EFI_PART_SIZE_MIB="$EFI_PART_SIZE_MIB" \
    BOOT_PART_SIZE_MIB="$BOOT_PART_SIZE_MIB" \
    ROOT_FILESYSTEM_TYPE="$ROOT_FILESYSTEM_TYPE" \
    HOME_FILESYSTEM_TYPE="$HOME_FILESYSTEM_TYPE" \
    WANT_SWAP="$WANT_SWAP" \
    WANT_HOME_PARTITION="$WANT_HOME_PARTITION" \
    PARTITION_UUIDS_EFI_UUID="$PARTITION_UUIDS_EFI_UUID" \
    PARTITION_UUIDS_EFI_PARTUUID="$PARTITION_UUIDS_EFI_PARTUUID" \
    PARTITION_UUIDS_ROOT_UUID="$PARTITION_UUIDS_ROOT_UUID" \
    PARTITION_UUIDS_BOOT_UUID="$PARTITION_UUIDS_BOOT_UUID" \
    PARTITION_UUIDS_SWAP_UUID="$PARTITION_UUIDS_SWAP_UUID" \
    PARTITION_UUIDS_HOME_UUID="$PARTITION_UUIDS_HOME_UUID" \
    PARTITION_UUIDS_LUKS_CONTAINER_UUID="$PARTITION_UUIDS_LUKS_CONTAINER_UUID" \
    PARTITION_UUIDS_LV_ROOT_UUID="$PARTITION_UUIDS_LV_ROOT_UUID" \
    PARTITION_UUIDS_LV_SWAP_UUID="$PARTITION_UUIDS_LV_SWAP_UUID" \
    PARTITION_UUIDS_LV_HOME_UUID="$PARTITION_UUIDS_LV_HOME_UUID" \
    LV_ROOT_PATH="$LV_ROOT_PATH" \
    LV_SWAP_PATH="$LV_SWAP_PATH" \
    LV_HOME_PATH="$LV_HOME_PATH" \
    VG_NAME="$VG_NAME" \
    LV_LAYOUT_LV_ROOT="$LV_LAYOUT_LV_ROOT" \
    LV_LAYOUT_LV_SWAP="$LV_LAYOUT_LV_SWAP" \
    LV_LAYOUT_LV_HOME="$LV_LAYOUT_LV_HOME" \
    /usr/bin/arch-chroot /mnt /bin/bash "$chroot_target_dir/chroot_config.sh" || error_exit "Chroot configuration failed."

    log_info "Chroot setup complete."
    # Stage 5: Finalization
    log_header "Stage 5: Finalizing Installation"
    final_cleanup || error_exit "Final cleanup failed."

    log_success "Arch Linux installation complete! You can now reboot."
    prompt_reboot_system
}
# Helper function for base system installation
install_base_system_target() {
    log_info "Installing base system packages into /mnt..."
    
    local packages_to_install=() # Initialize an array to hold all packages

    # Add essential base packages
    if [[ ${#BASE_PACKAGES_ESSENTIAL[@]} -gt 0 ]]; then
        packages_to_install+=(${BASE_PACKAGES_ESSENTIAL[@]})
    fi

    local kernel_packages=()
    if [ "$KERNEL_TYPE" == "linux" ]; then
        kernel_packages+=(${BASE_PACKAGES_KERNEL_LINUX[@]})
    elif [ "$KERNEL_TYPE" == "linux-lts" ]; then
        kernel_packages+=(${BASE_PACKAGES_KERNEL_LTS[@]})
    else
        error_exit "Unsupported KERNEL_TYPE: $KERNEL_TYPE."
    fi
    if [[ ${#kernel_packages[@]} -gt 0 ]]; then
        packages_to_install+=(${kernel_packages[@]})
    fi
    
    # Add bootloader, network, and general system utilities
    if [ "$BOOTLOADER_TYPE" == "grub" ]; then
        packages_to_install+=(${BASE_PACKAGES_BOOTLOADER_GRUB[@]})
    fi
    if [ "$BOOTLOADER_TYPE" == "systemd-boot" ]; then
        packages_to_install+=(${BASE_PACKAGES_BOOTLOADER_SYSTEMDBOOT[@]})
    fi
    packages_to_install+=(${BASE_PACKAGES_NETWORK[@]})
    packages_to_install+=(${BASE_PACKAGES_SYSTEM_UTILS[@]})

    # Install LVM/RAID tools if chosen
    if [ "$WANT_LVM" == "yes" ]; then
        packages_to_install+=(${BASE_PACKAGES_LVM[@]})
    fi
    if [ "$WANT_RAID" == "yes" ]; then
        packages_to_install+=(${BASE_PACKAGES_RAID[@]})
    fi
    
    # Add Filesystem utilities based on user choice
    if [ "$ROOT_FILESYSTEM_TYPE" == "btrfs" ]; then
        packages_to_install+=(${BASE_PACKAGES_FS_BTRFS[@]})
    elif [ "$ROOT_FILESYSTEM_TYPE" == "xfs" ]; then
        packages_to_install+=(${BASE_PACKAGES_FS_XFS[@]})
    fi
    
    if [ "$WANT_HOME_PARTITION" == "yes" ]; then
        if [ "$HOME_FILESYSTEM_TYPE" == "btrfs" ]; then
            packages_to_install+=(${BASE_PACKAGES_FS_BTRFS[@]})
        elif [ "$HOME_FILESYSTEM_TYPE" == "xfs" ]; then
            packages_to_install+=(${BASE_PACKAGES_FS_XFS[@]})
        fi
    fi
    
    if [ ${#packages_to_install[@]} -eq 0 ]; then
        error_exit "No packages compiled for base system installation. This should not happen."
    fi

    run_pacstrap_base_install "${packages_to_install[@]}" || error_exit "Base system installation failed."

    generate_fstab # Call the fstab generation after base install, before chroot.

    log_info "Base system installation complete on target."
}

# --- Call the main function ---
main "$@"
}
