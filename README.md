# 🏠 Dotfiles — mawathilde (⚠️ WIP ⚠️)

My personal dotfiles for a minimal, fully encrypted Arch Linux setup with [Hyprland](https://github.com/hyprwm/Hyprland).

> ⚠️ These configs are tailored for my machines.  
> If you're reusing them, make sure to **review everything before applying**.


## 🛠 Structure

This repository uses [chezmoi](https://www.chezmoi.io/) to manage dotfiles.

```bash
chezmoi init --apply mawathilde
```

## 📦 Software

My system is based on:

- 🧊 **Hyprland** (Wayland WM)
- 🎨 **Waybar**, **wofi**
- 🌐 **NetworkManager**
- 🧪 **Zsh**

## 📓 Setup Notes

For a full installation guide, see:

- [`INSTALLATION.md`](./INSTALLATION.md) → Disk, encryption, btrfs, systemd-boot

## 🖥 Multi-device Support (WIP)

My Hyprland config supports different monitor setups (desktop, laptop, VM).  
I manage this using `hostname` detection or custom scripts in the `scripts/` folder.

You can adapt `monitors.conf` to your needs.

## 🤝 License

MIT — free to use, but attribution is appreciated.