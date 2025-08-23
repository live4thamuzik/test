#!/bin/bash
# config.sh - All configurable options and package lists for Archl4tm (Bash 3.x Compatible)

# --- Installation Parameters (Populated by dialogs.sh or defaults) ---
INSTALL_DISK=""               # Primary disk selected by user (e.g., /dev/sda). Blank initially.
OVERRIDE_BOOT_MODE="no"       # "yes" if user forces BIOS mode. Default to "no".
BOOT_MODE="uefi"              # "uefi" or "bios" (auto-detected, can be overridden). Default to "uefi".
WANT_WIFI_CONNECTION="no"     # "yes" or "no". Default to "no".

PARTITION_SCHEME=""           # e.g., "auto_simple", "auto_luks_lvm", "auto_raid_luks_lvm", "manual". Blank initially.
WANT_SWAP="no"                # "yes" or "no". Default to "no".
WANT_HOME_PARTITION="no"      # "yes" or "no". Default to "no".
WANT_ENCRYPTION="no"          # "yes" or "no" (implied by scheme). Default to "no".
WANT_LVM="no"                 # "yes" or "no" (implied by scheme). Default to "no".
WANT_RAID="no"                # "yes" or "no" (implied by scheme). Default to "no".
LUKS_PASSPHRASE=""            # Populated by secure_password_input. Blank initially.
RAID_LEVEL=""                 # e.g., "1", "5". Blank initially.
RAID_DEVICES=()               # Array of disks for RAID, if applicable. Empty initially.

# Default Partition Sizes (for auto-partitioning schemes) - in MiB for parted calculations
EFI_PART_SIZE_MIB=1024         # 1024 MiB for EFI partition
BOOT_PART_SIZE_MIB=2048       # 2048 MiB (2 GiB) for /boot partition

# Filesystem types for root and home partitions - will be selected by user
ROOT_FILESYSTEM_TYPE="ext4"   # Default FS for root, will be overridden by prompt
HOME_FILESYSTEM_TYPE="ext4"   # Default FS for /home, will be overridden by prompt

KERNEL_TYPE="linux"           # "linux" or "linux-lts". Default to "linux".
CPU_MICROCODE_TYPE="none"     # "intel", "amd", or "none" (auto-detected). Default to "none".

TIMEZONE_DEFAULT="America/New_York" # Default timezone
TIMEZONE="$TIMEZONE_DEFAULT"        # Populated by dialogs.sh. Uses default initially.
LOCALE="en_US.UTF-8"          # Default locale.
KEYMAP="us"                   # Default console keymap.

REFLECTOR_COUNTRY_CODE="US"   # Default country for reflector mirrors.

SYSTEM_HOSTNAME=""            # Populated by dialogs.sh. Blank initially.
ROOT_PASSWORD=""              # Populated by dialogs.sh (securely handled). Blank initially.
MAIN_USERNAME=""              # Populated by dialogs.sh. Blank initially.
MAIN_USER_PASSWORD=""         # Populated by dialogs.sh. Blank initially.

DESKTOP_ENVIRONMENT=""        # e.g., "gnome", "kde", "hyprland", "none". Blank initially.
DISPLAY_MANAGER=""            # e.g., "gdm", "sddm", "none". Blank initially.
GPU_DRIVER_TYPE="none"        # "amd", "nvidia", "intel", or "none" (auto-detected). Default to "none".

BOOTLOADER_TYPE="grub"        # "grub" or "systemd-boot". Default to "grub".
ENABLE_OS_PROBER="no"         # "yes" or "no" (for GRUB dual-boot). Default to "no".

WANT_MULTILIB="no"            # "yes" or "no". Default to "no".
WANT_AUR_HELPER="no"          # "yes" or "no". Default to "no".
AUR_HELPER_CHOICE=""          # e.g., "yay", "paru". Blank initially.
WANT_FLATPAK="no"             # "yes" or "no". Default to "no".

INSTALL_CUSTOM_PACKAGES="no"  # "yes" or "no". Default to "no".
CUSTOM_PACKAGES=""            # Space-separated list of custom official packages. User modifies directly in this file.
INSTALL_CUSTOM_AUR_PACKAGES="no" # "yes" or "no". Default to "no".
CUSTOM_AUR_PACKAGES=""        # Space-separated list of custom AUR packages. User modifies directly in this file.

WANT_GRUB_THEME="no"          # "yes" or "no". Default to "no".
GRUB_THEME_CHOICE=""          # e.g., "Vimix", "Poly-light". Blank initially.

WANT_NUMLOCK_ON_BOOT="no"     # "yes" or "no". Default to "no".

# --- Dotfile Deployment (for fully themed installs) ---
WANT_DOTFILES_DEPLOYMENT="no" # "yes" or "no"
DOTFILES_REPO_URL=""          # Git repository URL for dotfiles (e.g., "https://github.com/youruser/dotfiles.git")
DOTFILES_BRANCH="main"        # Branch to clone (e.g., "main", "hyprland-config")


# --- Internal State Variables (Populated by functions, not user choices) ---
# For Bash 3.x, associative arrays are replaced by indexed arrays with explicit names.
PARTITION_UUIDS_EFI_UUID=""
PARTITION_UUIDS_EFI_PARTUUID=""
PARTITION_UUIDS_ROOT_UUID=""
PARTITION_UUIDS_BOOT_UUID=""
PARTITION_UUIDS_SWAP_UUID=""
PARTITION_UUIDS_HOME_UUID=""
PARTITION_UUIDS_LUKS_CONTAINER_UUID=""
PARTITION_UUIDS_LV_ROOT_UUID=""
PARTITION_UUIDS_LV_SWAP_UUID=""
PARTITION_UUIDS_LV_HOME_UUID=""

# For Bash 3.x, maps like LUKS_DEVICES_MAP are replaced by explicit variable assignment.
LUKS_CRYPTROOT_DEV="" # /dev/mapper/cryptroot, for the single main LUKS container

# For Bash 3.x, LVM_DEVICES_MAP is replaced by specific LV path variables.
LV_ROOT_PATH=""     # Populated dynamically by setup_lvm
LV_SWAP_PATH=""     # Populated dynamically by setup_lvm
LV_HOME_PATH=""     # Populated dynamically by setup_lvm

VG_NAME="volgroup0" # Default LVM Volume Group name (from your old script)


# --- Options for Dialogs (Indexed Arrays of space-separated strings) ---

# Partitioning strategies: strings where key and value are separated for manual lookup.
# For example, PARTITION_STRATEGY_FUNCTIONS[0]="auto_simple", PARTITION_STRATEGY_FUNCTIONS[1]="do_auto_simple_partitioning"
declare -a PARTITION_STRATEGY_FUNCTIONS=(
    "auto_simple" "do_auto_simple_partitioning"
    "auto_luks_lvm" "do_auto_luks_lvm_partitioning"
    "auto_raid_luks_lvm" "do_auto_raid_luks_lvm_partitioning"
    "manual" "do_manual_partitioning_guided"
)


# Partitioning strategies that the script supports
declare -a PARTITION_STRATEGIES_OPTIONS=(
    "auto_simple"
    "auto_luks_lvm"
    "manual"
)
# Note: "auto_raid_luks_lvm" will be conditionally added in dialogs.sh based on disk count


# RAID levels (for mdadm software RAID)
declare -a RAID_LEVEL_OPTIONS=("1" "5" "6" "10")

# Filesystem types available for selection (primarily for root/home)
declare -a FILESYSTEM_OPTIONS=(
    "ext4"
    "btrfs"
    "xfs"
)

# Kernel types for installation
declare -a KERNEL_TYPES_OPTIONS=("linux" "linux-lts")

# Timezone top-level regions (for initial selection)
declare -a TIMEZONE_REGIONS=(
    "Africa"
    "America"
    "Antarctica"
    "Arctic"
    "Asia"
    "Atlantic"
    "Australia"
    "Europe"
    "Indian"
    "Pacific"
)

# Common locales. Add/remove as needed. 'en_US.UTF-8' is standard.
declare -a LOCALE_OPTIONS=(
    "en_US.UTF-8"
    "en_GB.UTF-8"
    "de_DE.UTF-8"
    "fr_FR.UTF-8"
    "es_ES.UTF-8"
    "ja_JP.UTF-8"
    "zh_CN.UTF-8"
)

# Common console keymaps. Can be expanded based on 'localectl list-keymaps'.
declare -a KEYMAP_OPTIONS=(
    "us" "de" "fr" "es" "gb" "jp"
)

# Common countries for Reflector.
declare -a REFLECTOR_COMMON_COUNTRIES=(
    "US" "CA" "MX" "BR"
    "DE" "FR" "GB" "IT" "NL"
    "AU" "NZ"
    "IN" "JP" "KR" "SG"
    "ZA"
)

# Options for Desktop Environment Selection
declare -a DESKTOP_ENVIRONMENTS_OPTIONS=(
    "gnome"
    "kde"
    "hyprland"
    "none"
)

# Options for Desktop Environment Selection
declare -a DISPLAY_MANAGER_OPTIONS=(
    "gdm"
    "sddm"
    "none"
)

# Bootloader options
declare -a BOOTLOADER_TYPES_OPTIONS=("grub" "systemd-boot")

# AUR Helper options
declare -a AUR_HELPERS_OPTIONS=("yay" "paru")

# GRUB Theme Options
declare -a GRUB_THEME_OPTIONS=(
    "PolyDark"
    "CyberEXS"
    "CyberPunk"
    "HyperFluent"
)

# --- Package Lists (Indexed Arrays of space-separated strings) ---
# Each variable name indicates the choice (e.g., _GNOME_PACKAGES).
# To access, use: ${DESKTOP_ENVIRONMENTS_GNOME_PACKAGES[@]}

declare -a BASE_PACKAGES_ESSENTIAL=("base")
declare -a BASE_PACKAGES_BOOTLOADER_GRUB=("grub" "efibootmgr" "os-prober")
declare -a BASE_PACKAGES_BOOTLOADER_SYSTEMDBOOT=("systemd-boot")
declare -a BASE_PACKAGES_NETWORK=("networkmanager" "dhcpcd")
declare -a BASE_PACKAGES_SYSTEM_UTILS=("sudo" "man-db" "man-pages" "vim" "nano" "bash-completion" "git")
# CPU Microcode packages (installed conditionally based on detection)
declare -a BASE_PACKAGES_FIRMWARE_INTEL=("intel-ucode")
declare -a BASE_PACKAGES_FIRMWARE_AMD=("amd-ucode")
# LVM and RAID tools (needed if chosen in partitioning scheme)
declare -a BASE_PACKAGES_LVM=("lvm2")
declare -a BASE_PACKAGES_RAID=("mdadm")
# Basic filesystem utilities
declare -a BASE_PACKAGES_FS_EXT4=("e2fsprogs")
declare -a BASE_PACKAGES_FS_BTRFS=("btrfs-progs")
declare -a BASE_PACKAGES_FS_XFS=("xfsprogs")


# Desktop Environments and their core packages (indexed arrays of package names)
declare -a DESKTOP_ENVIRONMENTS_GNOME_PACKAGES=("gnome" "gnome-extra" "gnome-tweaks" "gnome-shell-extensions" "gnome-browser-connector" "firefox")
declare -a DESKTOP_ENVIRONMENTS_KDE_PACKAGES=("plasma-desktop" "kde-applications" "dolphin" "firefox" "lxappearance")
# Hyprland specific list - Bash 3.x compatible long string
declare -a DESKTOP_ENVIRONMENTS_HYPRLAND_PACKAGES=(
    "hyprland" "hyprland-protocols" "xdg-desktop-portal-hyprland"
    "hypridle" "hyprlock" "hyprpicker" "hyprshade" "hyprsunset" "cliphist" "grim" "grimblast-git" "slurp" "swappy" "swww" "swaylockeffects-git" "swayosd-git" "wlogout"
    "kitty" "waybar" "wofi" "mako" "dunst"
    "pipewire" "wireplumber" "pipewire-alsa" "pipewire-audio" "pipewire-jack" "pipewire-pulse" "pipewire-v4l2" "gst-plugin-pipewire" "pamixer" "pavucontrol"
    "network-manager-applet"
    "brightnessctl" "udiskie"
    "polkit-gnome"
    "qt5-wayland" "qt6-wayland" "kvantum" "kvantum-qt5" "qt5ct" "qt6ct"
    "nwg-look" "nwg-displays" "bluez" "bluez-utils" "blueman"
    "ttf-firacode-nerd" "ttf-font-awesome" "ttf-meslo-nerd" "noto-fonts-emoji" "ttf-anonymouspro-nerd" "ttf-daddytime-mono-nerd"
    "dolphin" "rofi-wayland" "satty" "imagemagick"
    "wlr-protocols" "wlr-randr"
    "xdg-desktop-portal-gtk" "libnotify"
)
declare -a DESKTOP_ENVIRONMENTS_NONE_PACKAGES=("")

# Display Managers (indexed arrays of package names)
declare -a DISPLAY_MANAGERS_GDM_PACKAGES=("gdm")
declare -a DISPLAY_MANAGERS_SDDM_PACKAGES=("sddm")
declare -a DISPLAY_MANAGERS_NONE_PACKAGES=("")


# GPU Drivers (indexed arrays of package names)
declare -a GPU_DRIVERS_AMD_PACKAGES=("xf86-video-amdgpu" "mesa" "vulkan-radeon")
declare -a GPU_DRIVERS_NVIDIA_PACKAGES=("nvidia" "nvidia-utils" "nvidia-settings")
declare -a GPU_DRIVERS_INTEL_PACKAGES=("xf86-video-intel" "mesa" "vulkan-intel")
declare -a GPU_DRIVERS_NONE_PACKAGES=("")


# AUR Helper packages (AUR_HELPERS_OPTIONS lists choices, these are actual package names)
declare -a AUR_HELPERS_YAY_PACKAGES=("yay")
declare -a AUR_HELPERS_PARU_PACKAGES=("paru")

# Flatpak package
FLATPAK_PACKAGE="flatpak" # Still a scalar variable

# Custom packages specified by the user to be installed from Arch repos
CUSTOM_PACKAGES="" # Still a scalar variable

# Custom AUR packages specified by the user to be installed via AUR helper
CUSTOM_AUR_PACKAGES="" # Still a scalar variable

# GRUB Theme specific directories/files (indexed arrays for Bash 3.x)
# Format: variable_name=(git_url path/to/theme.txt_relative_to_repo_root)
declare -a GRUB_THEME_SOURCES_POLY_DARK=("https://github.com/shvchk/poly-dark.git" "theme.txt")
declare -a GRUB_THEME_SOURCES_CYBEREXS=("https://github.com/HenriqueLopes42/themeGrub.CyberEXS.git" "theme.txt")
declare -a GRUB_THEME_SOURCES_CYBERPUNK=("https://gitlab.com/anoopmsivadas/Cyberpunk-GRUB-Theme.git" "Cyberpunk/theme.txt")
declare -a GRUB_THEME_SOURCES_HYPERFLUENT=("https://github.com/Coopydood/HyperFluent-GRUB-Theme.git" "arch/theme.txt")
declare -a GRUB_THEME_SOURCES_DEFAULT=("")


# --- mkinitcpio Hooks (Dynamic components based on features) ---
INITCPIO_BASE_HOOKS="base udev autodetect modconf block keyboard keymap filesystems fsck"
INITCPIO_LUKS_HOOK="encrypt"
INITCPIO_LVM_HOOK="lvm2"
INITCPIO_RAID_HOOK="mdadm_udev"
INITCPIO_NVME_HOOK="nvme"


# --- GRUB Kernel Command Line Parameters ---
GRUB_CMDLINE_LUKS_BASE="cryptdevice=UUID=<LUKS_CONTAINER_UUID>:cryptroot"
GRUB_CMDLINE_LVM_ON_LUKS="rd.lvm.vg=$VG_NAME"


# --- Default Logical Volume Layout (for LVM schemes) ---
# Direct scalar variables for Bash 3.x
LV_LAYOUT_LV_ROOT="100G"
LV_LAYOUT_LV_SWAP="4G"
LV_LAYOUT_LV_HOME="100%FREE"

# Default mount points for Logical Volumes (indexed arrays are still fine)
DEFAULT_LV_MOUNTPOINTS_LV_ROOT="/mnt"
DEFAULT_LV_MOUNTPOINTS_LV_SWAP="[SWAP]"
DEFAULT_LV_MOUNTPOINTS_LV_HOME="/mnt/home"

# Default filesystem types for Logical Volumes (indexed arrays are still fine)
DEFAULT_LV_FSTYPES_LV_ROOT="$ROOT_FILESYSTEM_TYPE"
DEFAULT_LV_FSTYPES_LV_SWAP="swap"
DEFAULT_LV_FSTYPES_LV_HOME="$HOME_FILESYSTEM_TYPE"
}
