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
    log_header "Arch Linux Automated Installer"

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

# This is where we'll define the script's root directory.
# It uses BASH_SOURCE to get the location of the currently executing script.
local script_root_dir="$(dirname "${BASH_SOURCE[0]}")"

# This variable will define the directory name inside the chroot where the scripts will be copied.
local chroot_target_dir="archinstall"
local install_script_path_in_chroot="/mnt/$chroot_target_dir"

log_info "Creating chroot script directory at $install_script_path_in_chroot..."
mkdir -p "$install_script_path_in_chroot" || error_exit "Failed to create target directory '$install_script_path_in_chroot'."

# Use a single `cp` command to copy all necessary scripts.
# We'll copy all .sh files from the source directory.
log_info "Copying chroot configuration files from '$script_root_dir' to '$install_script_path_in_chroot'..."
cp -v "$script_root_dir/"*.sh "$install_script_path_in_chroot/" || error_exit "Failed to copy all necessary scripts to chroot."

# Verify the files exist at the destination
if [ ! -f "$install_script_path_in_chroot/chroot_config.sh" ] || \
   [ ! -f "$install_script_path_in_chroot/config.sh" ] || \
   [ ! -f "$install_script_path_in_chroot/utils.sh" ]; then
    error_exit "One or more required script files not found in destination directory after copying."
fi

log_info "Setting permissions for chroot scripts..."
# We can use a single `find` command to find all the copied files
# and apply the executable permission at once.
#find "$install_script_path_in_chroot" -type f -name "*.sh" -exec arch-chroot /mnt chmod +x {} \; || error_exit "Failed to make chroot scripts executable."
chmod +x "$install_script_path_in_chroot"/*.sh || error_exit "Failed to make chroot scripts executable."

log_info "Executing chroot configuration script inside chroot..."
run_in_chroot || error_exit "Chroot configuration failed."

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
