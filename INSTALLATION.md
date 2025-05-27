# ⚙️ Arch Linux Setup — Encrypted Btrfs Install

> **⚠️ Warning**  
> This is a personal installation guide tailored to my workflow and machines.  
> It assumes:
> - Disk = `/dev/vda`
> - French AZERTY keyboard
> - Full disk encryption with LUKS2
> - Btrfs with subvolumes
> - `systemd-boot` as bootloader 
> 
> You’re free to reuse and adapt this guide, but **review and edit commands to match your hardware and setup.**

## 1. Boot into Arch ISO

```bash
loadkeys fr
ping archlinux.org
```

---

## 2. Partition the Disk

```bash
disk="/dev/vda"

sgdisk -Z "$disk"
sgdisk -n 1::+512M -t 1:ef00 -c 1:EFI "$disk"
sgdisk -n 2::-0     -t 2:8300 -c 2:cryptroot "$disk"
```

---

## 3. Encrypt with LUKS

```bash
cryptsetup luksFormat ${disk}2
cryptsetup open ${disk}2 cryptroot
```

---

## 4. Format & Mount Btrfs

```bash
mkfs.fat -F32 ${disk}1
mkfs.btrfs /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@pkg
umount /mnt
```

```bash
mount -o compress=zstd,subvol=@        /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{boot,home,var/cache/pacman/pkg}
mount -o compress=zstd,subvol=@home    /dev/mapper/cryptroot /mnt/home
mount -o compress=zstd,subvol=@pkg     /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount ${disk}1 /mnt/boot
```

---

## 5. Install Base System

```bash
pacstrap -K /mnt base linux linux-firmware amd-ucode btrfs-progs zsh sudo vim
```

---

## 6. fstab & chroot

```bash
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt
```

---

## 7. System Config

```bash
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "fr_FR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=fr" > /etc/vconsole.conf
echo "hostname" > /etc/hostname
```

---

## 8. Initramfs (mkinitcpio)

Edit `/etc/mkinitcpio.conf` → HOOKS :

```ini
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole consolefont block filesystems sd-encrypt fsck) 
```

Then:

```bash
mkinitcpio -P
```

---

## 9. Bootloader (systemd-boot)

```bash
bootctl install
```

Create `/boot/loader/entries/arch.conf`:

```ini
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options cryptdevice=UUID=<UUID>:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw
```

Replace `<UUID>`:

```bash
blkid -s UUID -o value ${disk}2
```

---

## 10. Create User

```bash
passwd  # for root
useradd -m -G wheel mawa
passwd mawa
EDITOR=vim visudo  # uncomment: %wheel ALL=(ALL:ALL) ALL
```

---

## 11. Reboot

```bash
exit
umount -R /mnt
reboot
```
