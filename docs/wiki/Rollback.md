# rollback

*"undo! undo! undo!"*

## the 30-second recovery

before every bleeding edge upgrade, we take a btrfs snapshot. if anything breaks — kernel panic, driver crash, cursed build — you're back to stable in 30 seconds.

## how it works

```bash
# step 1: boot from USB or recovery (if system won't boot)
# or just reboot and select the old kernel from GRUB

# step 2: mount the btrfs root
sudo mount /dev/nvme0n1p2 -o subvolid=5 /mnt

# step 3: move the broken subvolume
sudo mv /mnt/@ /mnt/@.broken

# step 4: restore the snapshot
sudo btrfs subvolume snapshot /mnt/.snapshots/pre-bleeding-edge-YYYYMMDD /mnt/@

# step 5: reboot
sudo umount /mnt
sudo reboot
```

you're back to exactly where you were before the upgrade.

## finding your snapshot

```bash
sudo ls /.snapshots/
# example: pre-bleeding-edge-2026-04-09-1001
```

the upgrade.sh script names them with date and time.

## cleanup after rollback

```bash
# remove the broken subvolume (optional, saves space)
sudo mount /dev/nvme0n1p2 -o subvolid=5 /mnt
sudo btrfs subvolume delete /mnt/@.broken
sudo umount /mnt
```

## if you just need the old kernel

you don't need a full rollback to switch kernels. GRUB lists all installed kernels:

```bash
# reboot and select linux (6.19.x) instead of linux-mainline (7.0-rc)
sudo reboot

# or set default kernel in GRUB
sudo grub-set-default "Advanced options for Arch Linux>Arch Linux, with Linux linux"
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

## preventing the need for rollback

1. always `--dry-run` first
2. always snapshot before upgrading
3. keep the stable kernel installed alongside mainline
4. test one change at a time
5. check `journalctl -b` after reboot for errors

---

*next: [credits](Credits)*
