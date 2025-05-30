# ⚙️ Arch Linux Setup — Encrypted Btrfs Install

> **⚠️ Warning**  
> This is a personal installation guide tailored to my workflow and machines.  
> It assumes:
> - Disk = `/dev/vda`
> - French AZERTY keyboard
> - Full disk encryption with LUKS2
> - Btrfs with subvolumes
> - `grub` as bootloader 
> 
> You’re free to reuse and adapt this guide, but **review and edit commands to match your hardware and setup.**

# Preliminary Steps

First, boot into the Arch Linux installation media.  
Then, set the keyboard layout:
```zsh
loadkeys fr
```

Check if the system is booted in UEFI mode
```zsh
cat /sys/firmware/efi/fw_platform_size
```

Check network connectivity:
```zsh
ping -c 3 archlinux.org
```

# Installation Steps

## Partitioning

> **Note**: This guide uses `sgdisk` for partitioning.
> If you prefer `fdisk` or `parted`, adjust the commands accordingly.

| Type | Size |
| --- | --- |
| UEFI | 512MB |
| Linux Filesystem | Ramaining space |

```zsh

# Zap the disk.
sgdisk -Z "$disk"

# UEFI partition (512MB)
sgdisk -n 1::+512M -t 1:ef00 "$disk"

# Linux filesystem partition (remaining space)
sgdisk -n 2::-0     -t 2:8300 "$disk"
```

## Encryption

I encrypt the root partition with LUKS to keep everything secure. First, I format the partition, then I open it so it can be used for the rest of the setup.

```zsh
cryptsetup luksFormat /dev/vda2 # Confirm with 'YES' and set a passphrase.
cryptsetup open /dev/vda2 cryptroot # This creates a mapping at /dev/mapper/cryptroot
```

## Formatting

Now, I format the partitions. The first partition is formatted as FAT32 for UEFI, and the second partition is formatted as Btrfs.

Btrfs is a modern filesystem that supports features like snapshots and subvolumes, which are useful for managing system files and user data.

> **Note**: The `mkfs.btrfs` command will create a Btrfs filesystem on the encrypted partition, which is mapped to `/dev/mapper/cryptroot`.

```zsh
# Format the UEFI partition
mkfs.fat -F32 /dev/vda1

# Format the encrypted partition with Btrfs
mkfs.btrfs /dev/mapper/cryptroot

# Mount the Btrfs filesystem
mount /dev/mapper/cryptroot /mnt
```

## Mounting Subvolumes

```zsh
# Create the subvolumes, I choose to create subvolumes for / and /home.
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home

# Unmount the root fs
umount /mnt
```

I'll compress the subvolumes using **zstd** for better performance and space efficiency.

```zsh
# Mount the root and home subvolumes with compression
mount -o compress=zstd,subvol=@ /dev/mapper/cryptroot /mnt

mkdir -p /mnt/home
mount -o compress=zstd,subvol=@home /dev/mapper/cryptroot /mnt/home
```

I'll also create a mount point for the boot partition and mount it.
I choose to use the `/boot` directory for the UEFI partition. 

> **Note**: It may be useful to use /boot/efi. To be able to restore the kernel with @ subvolume. **I plan to do this in the future.**

```zsh
mkdir -p /mnt/boot
mount /dev/vda1 /mnt/boot
```

## Packages installation

```zsh
# This will install the base system, kernel, firmware, and some essential tools.
# "base, linux, linux-firmware" are the essential packages for a minimal Arch Linux installation
# base-devel" base development packages
# amd-ucode: AMD microcode for CPU updates. Use "intel-ucode" for Intel CPUs.
# git: version control system  
# btrfs-progs: Btrfs filesystem utilities  
# cryptsetup: LUKS encryption tools  
# grub: bootloader  
# efibootmgr: EFI boot management  
# grub-btrfs: detects Btrfs snapshots  
# inotify-tools: filesystem event monitoring  
# timeshift: system snapshot utility  
# networkmanager: network management  
# pipewire: audio server
# wireplumber: session manager for PipeWire  
# reflector: updates mirrorlist  
# zsh: alternative shell  
# zsh-completions: extra completions for Zsh  
# zsh-autosuggestions: command suggestions  
# openssh: SSH client and server  
# man: manual pages  
# sudo: run commands as root  
# nano: text editor
pacstrap -K /mnt base base-devel linux linux-firmware amd-ucode git btrfs-progs cryptsetup grub efibootmgr grub-btrfs inotify-tools timeshift networkmanager pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber reflector zsh zsh-completions zsh-autosuggestions openssh man sudo nano
```


## Fstab

```zsh
# Fetch the current mount points and generate the fstab file.
# The -U option uses UUIDs for the partitions, which is recommended for stability.
genfstab -U /mnt >> /mnt/etc/fstab

# Verify the fstab file
cat /mnt/etc/fstab
```

## Chroot into the new system

```zsh
# Change root into the new system
arch-chroot /mnt
```

## Timezone

```zsh
# Set the timezone to Paris
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime

# Synchronize the hardware clock with the system clock
hwclock --systohc
```

## TTY keymap

To make sure the keyboard layout is set correctly in the console, I need to create a keymap file.

```zsh
echo "KEYMAP=fr" > /etc/vconsole.conf
```

## Hostname

```zsh
echo "archlinux" > /etc/hostname
```

## Initramfs configuration

To ensure the system can boot properly with the encrypted Btrfs filesystem, I need to edit the `mkinitcpio` configuration file.

Edit `/etc/mkinitcpio.conf` and modify the `HOOKS` and `MODULES` line to include the necessary hooks for encryption:

```ini
MODULES=(btrfs)

HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems encrypt fsck)
```

Then, regenerate the initramfs:

```zsh
mkinitcpio -P
```

## User & Passwords

```zsh
# Set the root password
passwd

# Create a new user and set its password
# -m creates a home directory
# -G wheel adds the user to the wheel group for sudo access
useradd -m -G wheel mawa
passwd mawa

# Edit the sudoers file to allow the wheel group to use sudo
EDITOR=nano visudo  # Uncomment the line: %wheel ALL=(ALL:ALL) ALL
```

## GRUB Bootloader

```zsh
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
```

Edit the GRUB configuration file `/etc/default/grub` to set these options:
```ini
GRUB_ENABLE_CRYPTODISK=y
GRUB_CMDLINE_LINUX="cryptdevice=UUID=<UUID>:cryptroot"
```

Replace `<UUID>` with the UUID of the encrypted partition:
```
blkid -s UUID -o value /dev/vda2
```

Then, generate the GRUB configuration file:
```zsh
grub-mkconfig -o /boot/grub/grub.cfg
```

## Clean up and exit

```zsh
# Enable NetworkManager service
systemctl enable NetworkManager

# Exit the chroot environment
exit

# Unmount all filesystems
umount -R /mnt

# Reboot the system
reboot
```