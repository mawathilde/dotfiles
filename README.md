# github.com/mawathilde/dotfiles

My dotfiles, managed with [`chezmoi`](https://github.com/twpayne/chezmoi).

## How to mount 'arch-install.sh' script inside a KVM virtual machine (for testing)

- Enable shared memory in KMV
- Create a filesystem pass-through to the host directory containing the script
- Mount the filesystem in the guest
```bash
mkdir chezmoi && mount -t virtiofs chezmoi chezmoi
```
