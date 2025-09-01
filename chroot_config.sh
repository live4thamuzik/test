#!/bin/bash
# chroot_config.sh - Functions for post-base-install (chroot) configurations
# This script is designed to be copied into the /mnt environment and executed by arch-chroot.

# Strict mode for this script
set -euo pipefail

# Source its own copy of config.sh and utils.sh from its copied location
source ./config.sh
source ./utils.sh

# Note: Variables like INSTALL_DISK, ROOT_PASSWORD, etc. are now populated from the environment passed by install_arch.sh
# Associative arrays like PARTITION_UUIDs are also exported (-A).
# So, they will be directly available in this script's scope.

# Re-define basic logging functions to ensure they are available within this script's context.
# These will override the log_* from utils.sh that might be sourced, but are safer for this context
# and ensure consistency if utils.sh is modified.
_log_info() { echo -e "\e[32m[INFO]\e[0m $(date +%T) $*"; }
_log_warn() { echo -e "\e[33m[WARN]\e[0m $(date +%T) $*" >&2; }
_log_error() { echo -e "\e[31m[ERROR]\e[0m $(date +%T) $*" >&2; exit 1; }
_log_success() { echo -e "\n\e[32;1m==================================================\e[0m\n\e[32;1m $* \e[0m\n\e[32;1m==================================================\e[0m\n"; }


# Main function for chroot configuration - this is now the entry point for this script
main_chroot_config() {
    _log_info "Starting chroot configurations within target system."

    # --- Phase 1: Basic System Configuration ---
    _log_info "Configuring time, locale, hostname, and basic user setup."

    _log_info "Setting system clock and timezone..."
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime || _log_error "Failed to set timezone symlink."
    hwclock --systohc || _log_error "Failed to sync hardware clock."

    _log_info "Setting localization (locale, keymap)..."
    echo "LANG=$LOCALE" > /etc/locale.conf || _log_error "Failed to set locale.conf."
    sed -i "/^#$(echo "$LOCALE" | sed 's/\./\\./g')/s/^#//" /etc/locale.gen || _log_error "Failed to uncomment locale in locale.gen."
    locale-gen || _log_error "Failed to generate locales."
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf || _log_error "Failed to set vconsole.conf."

    _log_info "Setting hostname and /etc/hosts..."
    echo "$SYSTEM_HOSTNAME" > /etc/hostname || _log_error "Failed to set hostname."
    echo "127.0.0.1 localhost" > /etc/hosts || _log_error "Failed to write to /etc/hosts."
    echo "::1       localhost" >> /etc/hosts || _log_error "Failed to append to /etc/hosts."
    echo "127.0.1.1 $SYSTEM_HOSTNAME.localdomain $SYSTEM_HOSTNAME" >> /etc/hosts || _log_error "Failed to append to /etc/hosts."
    _log_info "/etc/hosts configured."

    _log_info "Setting root password..."
    echo "root:$ROOT_PASSWORD" | chpasswd || _log_error "Failed to set root password."

    _log_info "Creating main user: $MAIN_USERNAME..."
    if id -u "$MAIN_USERNAME" &>/dev/null; then
        _log_warn "User '$MAIN_USERNAME' already exists. Skipping user creation."
    else
        useradd -m -G wheel -s /bin/bash "$MAIN_USERNAME" || _log_error "Failed to create user '$MAIN_USERNAME'."
        echo "$MAIN_USERNAME:$MAIN_USER_PASSWORD" | chpasswd || _log_error "Failed to set password for '$MAIN_USERNAME'."
        echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel-sudo || _log_error "Failed to configure sudoers."
        chmod 0440 /etc/sudoers.d/10-wheel-sudo || _log_error "Failed to set permissions on sudoers file."
    fi

    # --- Phase 2: Bootloader & Initramfs ---
    _log_info "Configuring bootloader, GRUB defaults, theme, and mkinitpio hooks."
    configure_bootloader_chroot || _log_error "Bootloader installation failed."

    configure_grub_defaults_chroot || _log_error "GRUB default configuration failed."

    configure_grub_theme_chroot || _log_error "GRUB theme configuration failed."

    configure_grub_cmdline_chroot || _log_error "GRUB kernel command line configuration failed."

    configure_mkinitpio_hooks_chroot || _log_error "Mkinitpio hooks configuration or initramfs rebuild failed."


    # --- Phase 3: Desktop Environment & Drivers ---
    _log_info "Installing Desktop Environment: $DESKTOP_ENVIRONMENT..."
    local de_packages=""
    case "$DESKTOP_ENVIRONMENT" in
        "gnome") de_packages="${DESKTOP_ENVIRONMENTS_GNOME_PACKAGES[@]}" ;;
        "kde") de_packages="${DESKTOP_ENVIRONMENTS_KDE_PACKAGES[@]}" ;;
        "hyprland") de_packages="${DESKTOP_ENVIRONMENTS_HYPRLAND_PACKAGES[@]}" ;;
        "none") de_packages="" ;;
    esac
    if [[ -n "$de_packages" ]]; then
        install_packages_chroot "$de_packages" || _log_error "Desktop Environment packages installation failed."
    fi

    _log_info "Installing Display Manager: $DISPLAY_MANAGER..."
    local dm_packages=""
    case "$DISPLAY_MANAGER" in
        "gdm") dm_packages="${DISPLAY_MANAGERS_GDM_PACKAGES[@]}" ;;
        "sddm") dm_packages="${DISPLAY_MANAGERS_SDDM_PACKAGES[@]}" ;;
        "none") dm_packages="" ;;
    esac
    if [[ -n "$dm_packages" ]]; then
        install_packages_chroot "$dm_packages" || _log_error "Display Manager packages installation failed."
        enable_systemd_service_chroot "$DISPLAY_MANAGER" || _log_error "Failed to enable Display Manager service."
    fi
    
    _log_info "Installing GPU Drivers..."
    install_gpu_drivers_chroot || _log_error "GPU driver installation failed."

    _log_info "Installing CPU Microcode..."
    install_microcode_chroot || _log_error "CPU Microcode installation failed."


    # --- Phase 4: Optional Software & User Customization ---
    _log_info "Enabling Multilib repository..."
    enable_multilib_chroot || _log_error "Multilib repository configuration failed."

    _log_info "Installing AUR Helper..."
    install_aur_helper_chroot || _log_error "AUR Helper installation failed."

    _log_info "Installing Flatpak..."
    install_flatpak_chroot || _log_error "Flatpak installation failed."

    _log_info "Installing Custom Packages..."
    install_custom_packages_chroot || _log_error "Custom packages installation failed."

    _log_info "Installing AUR Numlock on Boot..."
    configure_numlock_chroot || _log_error "Numlock on boot configuration failed."

    _log_info "Deploying Dotfiles..."
    deploy_dotfiles_chroot || _log_error "Dotfile deployment failed."

    _log_info "Saving mdadm.conf for RAID arrays..."
    save_mdadm_conf_chroot || _log_error "Mdadm.conf saving failed."

    # --- Phase 5: Final System Services ---
    _log_info "Enabling essential system services..."
    enable_systemd_service_chroot "NetworkManager" || _log_error "Failed to enable NetworkManager service."

    _log_success "Chroot configuration complete."
}
