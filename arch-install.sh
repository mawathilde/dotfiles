#!/bin/bash
# I was inspired by the following scripts:
# - https://github.com/maximbaz/dotfiles/blob/fedora/install.sh

# curl -sL https://install.mawathilde.fr | bash

set -u pipefail
trap 's=$?; [[ "$BASH_COMMAND" =~ ^umount ]] || { echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s; }' ERR

exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log" >&2)

CONFIGS_DIR="$( pwd )"/configs

MOUNT_OPTIONS="noatime,compress=zstd,ssd,commit=120"

# Dialog
BACKTITLE="Arch Linux installation"

get_input() {
	title="$1"
	description="$2"

	input=$(dialog --clear --stdout --backtitle "$BACKTITLE" --title "$title" --inputbox "$description" 0 0)
	echo "$input"
}

get_password() {
	title="$1"
	description="$2"

	init_pass=$(dialog --clear --stdout --backtitle "$BACKTITLE" --title "$title" --passwordbox "$description" 0 0)
	: ${init_pass:?"password cannot be empty"}

	test_pass=$(dialog --clear --stdout --backtitle "$BACKTITLE" --title "$title" --passwordbox "$description again" 0 0)
	if [[ "$init_pass" != "$test_pass" ]]; then
		echo "Passwords did not match" >&2
		exit 1
	fi
	echo $init_pass

}

get_choice() {
	title="$1"
	description="$2"
	shift 2
	options=("$@")
	dialog --clear --stdout --backtitle "$BACKTITLE" --title "$title" --menu "$description" 0 0 0 "${options[@]}"
}

echo -e "\n### Checking UEFI boot mode"
if [ ! -f /sys/firmware/efi/fw_platform_size ]; then
	echo >&2 "You must boot in UEFI mode to continue"
	exit 2
fi

echo -e "\n### Installing additional tools"
pacman -Sy --noconfirm archlinux-keyring 
pacman -Sy --noconfirm --needed pacman-contrib terminus-font
pacman -Sy --noconfirm git reflector dialog wget

echo -e "\n### HiDPI screens"
noyes=("Yes" "The font is too small" "No" "The font size is just fine")
hidpi=$(get_choice "Font size" "Is your screen HiDPI?" "${noyes[@]}") || exit 1
clear
[[ "$hidpi" == "Yes" ]] && font="ter-132n" || font="ter-716n"
setfont "$font"

hostname=$(get_input "Hostname" "Enter hostname") || exit 1
clear
: ${hostname:?"hostname cannot be empty"}

user=$(get_input "User" "Enter username") || exit 1
clear
: ${user:?"user cannot be empty"}

password=$(get_password "User" "Enter password") || exit 1
clear
: ${password:?"password cannot be empty"}

devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac | tr '\n' ' ')
read -r -a devicelist <<<$devicelist

device=$(get_choice "Installation" "Select installation disk" "${devicelist[@]}") || exit 1
clear

echo -ne "
-------------------------------------------------------------------------
                    Setting up France mirrors for faster downloads
-------------------------------------------------------------------------
"
reflector -a 48 -c France -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist
mkdir -p /mnt &>/dev/null # Hiding error message if any
echo -ne "
-------------------------------------------------------------------------
                    Installing Prerequisites
-------------------------------------------------------------------------
"
pacman -S --noconfirm --needed gptfdisk btrfs-progs glibc
echo -ne "
-------------------------------------------------------------------------
                    Formating Disk
-------------------------------------------------------------------------
"

umount -A --recursive /mnt &>/dev/null # Unmounting all mounted partitions

# disk prep
sgdisk -Z ${device} # zap all on disk
sgdisk -a 2048 -o ${device} # new gpt disk 2048 alignment

# create partitions
sgdisk -n 2::+500M --typecode=2:ef00 --change-name=2:'EFIBOOT' ${device} # partition 2 (UEFI Boot Partition)
sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT' ${device} # partition 3 (Root), default start, remaining
partprobe ${device} # reread partition table to ensure it is correct

# make filesystems
echo -ne "
-------------------------------------------------------------------------
                    Creating Filesystems
-------------------------------------------------------------------------
"

if [[ "${device}" =~ "nvme" ]]; then
    partition2=${device}p2
    partition3=${device}p3
else
    partition2=${device}2
    partition3=${device}3
fi

mkfs.ext4 ${partition3} # format root partition as ext4
mkfs.fat -F 32 ${partition2} # format boot partition as fat32

# mount target
mount ${partition3} /mnt # mount root
mount --mkdir ${partition2} /mnt/boot # mount boot

if ! grep -qs '/mnt' /proc/mounts; then
    echo "Drive is not mounted can not continue"
    echo "Rebooting in 3 Seconds ..." && sleep 1
    echo "Rebooting in 2 Seconds ..." && sleep 1
    echo "Rebooting in 1 Second ..." && sleep 1
    reboot now
fi

echo -ne "
-------------------------------------------------------------------------
                    Arch Install
-------------------------------------------------------------------------
"
pacstrap /mnt base base-devel linux linux-firmware man-db vim zsh nano archlinux-keyring wget efibootmgr grub --noconfirm --needed

# Network packages
pacstrap /mnt networkmanager dhclient resolvconf --noconfirm --needed
arch-chroot /mnt systemctl enable NetworkManager
echo "### Network Packages Installed"

if [ "$(lscpu | grep -o "AuthenticAMD")" == "AuthenticAMD" ]; then # Checking for AMD CPU
    pacstrap /mnt amd-ucode --noconfirm --needed
fi
if [ "$(lscpu | grep -o "Intel")" == "Intel" ]; then # Checking for Intel CPU
    pacstrap /mnt intel-ucode --noconfirm --needed
fi

# check graphics card
if lspci | grep -i "nvidia" &>/dev/null; then
    pacstrap /mnt nvidia nvidia-utils nvidia-settings --noconfirm --needed # install nvidia drivers
fi

cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

arch-chroot /mnt /bin/bash <<EOF
echo "${hostname}" > /etc/hostname
EOF


genfstab -L /mnt >> /mnt/etc/fstab
echo " 
  Generated /etc/fstab:
"
cat /mnt/etc/fstab

echo -ne "
-------------------------------------------------------------------------
                    Setting up User
-------------------------------------------------------------------------
"
arch-chroot /mnt /bin/bash <<EOF
echo "root:${password}" | chpasswd
EOF

arch-chroot /mnt useradd -m -s /bin/zsh $user
arch-chroot /mnt /bin/bash <<EOF
echo "${user}:${password}" | chpasswd
EOF

echo -ne "
-------------------------------------------------------------------------
                    Graphical Environment
-------------------------------------------------------------------------
"

pacstrap /mnt xorg xorg-server gdm gnome gnome-shell gnome-control-center gnome-terminal gnome-keyring gsettings-desktop-schemas --noconfirm --needed

arch-chroot /mnt systemctl enable gdm # enable gnome display manager
arch-chroot /mnt systemctl set-default graphical.target # set default target to graphical

arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc

locale-gen
echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
echo "KEYMAP=fr" > /etc/vconsole.conf

localectl --no-convert set-keymap fr
localectl --no-convert set-x11-keymap fr
EOF

arch-chroot /mnt mkinitcpio -P # generate the system images

arch-chroot /mnt gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'fr')]"

echo -ne "
-------------------------------------------------------------------------
                    GRUB Bootloader Install & Check
-------------------------------------------------------------------------
"

mkdir -p /mnt/boot/grub

arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

#arch-chroot /mnt mkinitcpio -P # generate the system images

echo -ne "
-------------------------------------------------------------------------
                    SYSTEM READY
-------------------------------------------------------------------------
"