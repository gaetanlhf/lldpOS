#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
OPENRC_DIR="$SCRIPT_DIR/openrc"

ALPINE_VERSION="3.23"
ALPINE_RELEASE="3.23.4"
ALPINE_ARCH="x86_64"
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine"

for cmd in wget tar xorriso grub-mkimage cpio xz mkfs.vfat; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd not found"
        echo "Install: apt install wget xorriso grub-pc-bin grub-efi-amd64-bin grub-common mtools dosfstools cpio xz-utils"
        exit 1
    fi
done

echo "=== Checking required files ==="
REQUIRED_SCRIPTS=(
    "generate-hostname.sh"
    "shell-welcome"
    "welcome"
    "keyconf"
    "dns-config"
    "nethelp"
    "dhcp-config"
    "static-ip"
    "vlan-create"
    "bond-create"
    "bridge-create"
    "lldp-display.sh"
    "lldpos-splash"
    "lldpos-shutdown"
    "ip-info"
    "port-test"
    "iface-reset"
)

REQUIRED_OPENRC=(
    "generate-hostname"
    "inittab"
)

MISSING=0

for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ ! -f "$SCRIPTS_DIR/$script" ]; then
        echo "Error: Missing script: scripts/$script"
        MISSING=1
    fi
done

for f in "${REQUIRED_OPENRC[@]}"; do
    if [ ! -f "$OPENRC_DIR/$f" ]; then
        echo "Error: Missing openrc file: openrc/$f"
        MISSING=1
    fi
done

if [ $MISSING -eq 1 ]; then
    echo ""
    echo "Build aborted: missing required files"
    exit 1
fi

echo "All required files found"
echo ""

WORK_DIR="/tmp/lldpos-build"
ROOTFS="$WORK_DIR/rootfs"
ISO_DIR="$WORK_DIR/iso"
OUTPUT_ISO="lldpOS.iso"

rm -rf "$WORK_DIR"
mkdir -p "$ROOTFS" "$ISO_DIR"

MINIROOTFS_URL="$ALPINE_MIRROR/v$ALPINE_VERSION/releases/$ALPINE_ARCH/alpine-minirootfs-$ALPINE_RELEASE-$ALPINE_ARCH.tar.gz"
MINIROOTFS_TARBALL="$WORK_DIR/alpine-minirootfs.tar.gz"

echo "=== Fetching Alpine minirootfs ==="
wget -q -O "$MINIROOTFS_TARBALL" "$MINIROOTFS_URL"

echo "=== Extracting minirootfs ==="
tar -xzf "$MINIROOTFS_TARBALL" -C "$ROOTFS"

echo "=== Configuring apk repositories ==="
cat > "$ROOTFS/etc/apk/repositories" << EOF
$ALPINE_MIRROR/v$ALPINE_VERSION/main
$ALPINE_MIRROR/v$ALPINE_VERSION/community
EOF

echo "=== Preparing chroot ==="
cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
mount --bind /proc "$ROOTFS/proc"
mount --bind /sys "$ROOTFS/sys"
mount --bind /dev "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"

cleanup_mounts() {
    set +e
    umount "$ROOTFS/dev/pts" 2>/dev/null
    umount "$ROOTFS/dev" 2>/dev/null
    umount "$ROOTFS/sys" 2>/dev/null
    umount "$ROOTFS/proc" 2>/dev/null
    set -e
}
trap cleanup_mounts EXIT

echo "=== Installing packages ==="
chroot "$ROOTFS" apk update
chroot "$ROOTFS" apk add --no-cache \
    alpine-base \
    bash \
    linux-lts \
    linux-firmware-bnx2 \
    linux-firmware-bnx2x \
    linux-firmware-realtek \
    linux-firmware-qlogic \
    linux-firmware-qed \
    linux-firmware-myricom \
    linux-firmware-netronome \
    lldpd \
    dialog \
    iputils \
    bind-tools \
    tcpdump \
    curl \
    wget \
    iproute2 \
    net-tools \
    traceroute \
    ethtool \
    iperf3 \
    mtr \
    kbd \
    kbd-bkeymaps \
    dhcpcd \
    less \
    nano \
    bash-completion

echo "=== Installing scripts ==="
mkdir -p "$ROOTFS/usr/local/bin"
cp "$SCRIPTS_DIR"/* "$ROOTFS/usr/local/bin/"
chmod +x "$ROOTFS/usr/local/bin"/*

echo "=== Installing bash completion ==="
mkdir -p "$ROOTFS/etc/bash_completion.d"
mv "$ROOTFS/usr/local/bin/lldpos-completion.bash" "$ROOTFS/etc/bash_completion.d/lldpos"

echo "=== Installing OpenRC service ==="
cp "$OPENRC_DIR/generate-hostname" "$ROOTFS/etc/init.d/generate-hostname"
chmod +x "$ROOTFS/etc/init.d/generate-hostname"

echo "=== Installing inittab ==="
cp "$OPENRC_DIR/inittab" "$ROOTFS/etc/inittab"

echo "=== Installing init script ==="
cat > "$ROOTFS/init" << 'EOFINIT'
#!/bin/sh
exec /sbin/init
EOFINIT
chmod +x "$ROOTFS/init"

echo "=== Creating version file ==="
date '+%Y.%m.%d' > "$ROOTFS/etc/lldpos-version"

echo "=== Configuring services ==="
chroot "$ROOTFS" /bin/sh << 'CHROOT'
rc-update add devfs sysinit
rc-update add dmesg sysinit
rc-update add hwdrivers sysinit
rc-update add modules boot
rc-update add hostname boot
rc-update add bootmisc boot
rc-update add syslog boot
rc-update add generate-hostname boot
rc-update add lldpd default
rc-update add networking default
passwd -d root
CHROOT

echo "=== Configuring bash ==="
cat > "$ROOTFS/root/.bashrc" << 'EOF'
if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
fi
EOF

echo "=== Configuring loopback interface ==="
mkdir -p "$ROOTFS/etc/network"
cat > "$ROOTFS/etc/network/interfaces" << 'EOF'
auto lo
iface lo inet loopback
EOF

echo "=== Configuring udev ==="
mkdir -p "$ROOTFS/etc/udev"
cat > "$ROOTFS/etc/udev/udev.conf" << 'EOF'
udev_log=err
event_timeout=10
EOF

echo "=== Blacklisting storage modules (network-only ISO) ==="
mkdir -p "$ROOTFS/etc/modprobe.d"
cat > "$ROOTFS/etc/modprobe.d/lldpos-no-storage.conf" << 'EOF'
blacklist nvme
blacklist nvme_core
blacklist ahci
blacklist libahci
blacklist sd_mod
blacklist sr_mod
blacklist usb_storage
blacklist uas
blacklist mmc_block
blacklist mmc_core
blacklist sdhci
blacklist sdhci_pci
blacklist floppy
blacklist virtio_blk
blacklist virtio_scsi
blacklist vmw_pvscsi
blacklist xen_blkfront
blacklist hv_storvsc
blacklist megaraid_sas
blacklist mpt3sas
blacklist mpt2sas
blacklist aacraid
blacklist hpsa
blacklist arcmsr
blacklist 3w_9xxx
blacklist qla2xxx
blacklist lpfc
EOF

echo "=== Releasing chroot mounts ==="
cleanup_mounts
trap - EXIT

echo "=== Wiping build-time traces ==="
cat > "$ROOTFS/etc/resolv.conf" << 'EOF'
# Configured at runtime by dhcpcd or dns-config
EOF
cat > "$ROOTFS/etc/hosts" << 'EOF'
127.0.0.1   localhost
::1         localhost
EOF
echo "localhost" > "$ROOTFS/etc/hostname"
: > "$ROOTFS/etc/machine-id"
rm -rf "$ROOTFS/var/lib/dbus" 2>/dev/null || true
rm -rf "$ROOTFS/var/log"/* 2>/dev/null || true
rm -rf "$ROOTFS/tmp"/* 2>/dev/null || true
rm -rf "$ROOTFS/var/tmp"/* 2>/dev/null || true
rm -rf "$ROOTFS/var/cache"/* 2>/dev/null || true
rm -rf "$ROOTFS/var/spool"/* 2>/dev/null || true
rm -rf "$ROOTFS/var/empty"/* 2>/dev/null || true
rm -rf "$ROOTFS/root/".[!.]* 2>/dev/null || true
rm -rf "$ROOTFS/home"/*/.[!.]* 2>/dev/null || true
rm -f "$ROOTFS/var/lib/apk/lock" 2>/dev/null || true
rm -f "$ROOTFS/var/lib/apk/scripts.tar" 2>/dev/null || true
rm -f "$ROOTFS/var/lib/misc/random-seed" 2>/dev/null || true
rm -f "$ROOTFS/etc/ssh"/ssh_host_* 2>/dev/null || true
rm -f "$ROOTFS/etc/passwd-" "$ROOTFS/etc/shadow-" "$ROOTFS/etc/group-" "$ROOTFS/etc/gshadow-" 2>/dev/null || true
rm -f "$ROOTFS/etc/.pwd.lock" 2>/dev/null || true
rm -f "$ROOTFS/etc/mtab" 2>/dev/null || true
ln -sf /proc/mounts "$ROOTFS/etc/mtab"
rm -f "$ROOTFS"/.dockerenv 2>/dev/null || true
rm -f "$ROOTFS"/.dockerinit 2>/dev/null || true
find "$ROOTFS" -name ".bash_history" -delete 2>/dev/null || true
find "$ROOTFS" -name ".ash_history" -delete 2>/dev/null || true
find "$ROOTFS" -name ".wget-hsts" -delete 2>/dev/null || true
find "$ROOTFS" -name ".python_history" -delete 2>/dev/null || true

echo "=== Cleaning rootfs ==="
rm -rf "$ROOTFS/var/cache/apk"/* 2>/dev/null || true
rm -rf "$ROOTFS/usr/share/man"/* 2>/dev/null || true
rm -rf "$ROOTFS/usr/share/doc"/* 2>/dev/null || true
rm -rf "$ROOTFS/lib/modules"/*/build 2>/dev/null || true
rm -rf "$ROOTFS/lib/modules"/*/source 2>/dev/null || true
rm -f "$ROOTFS/boot/initramfs-"* 2>/dev/null || true

echo "=== Removing unused kernel modules (network-only) ==="
KVER=$(ls "$ROOTFS/lib/modules" | head -n1)
MODBASE="$ROOTFS/lib/modules/$KVER/kernel"
for dir in \
    drivers/ata \
    drivers/scsi \
    drivers/nvme \
    drivers/block \
    drivers/mmc \
    drivers/md \
    drivers/firewire \
    drivers/target \
    drivers/media \
    drivers/staging \
    drivers/infiniband \
    drivers/bluetooth \
    drivers/nvdimm \
    drivers/usb/storage \
    drivers/input/joystick \
    drivers/input/touchscreen \
    drivers/input/gameport \
    drivers/input/tablet \
    drivers/parport \
    drivers/isdn \
    drivers/pcmcia \
    drivers/memstick \
    drivers/auxdisplay \
    drivers/accessibility \
    drivers/net/wireless \
    drivers/net/can \
    drivers/net/hamradio \
    drivers/net/ppp \
    drivers/net/slip \
    drivers/net/plip \
    drivers/net/wan \
    drivers/net/wwan \
    drivers/net/fddi \
    drivers/net/arcnet \
    drivers/net/appletalk \
    drivers/net/fjes \
    drivers/atm \
    drivers/nfc \
    drivers/macintosh \
    drivers/w1 \
    drivers/hsi \
    drivers/most \
    drivers/rapidio \
    drivers/sbus \
    drivers/siox \
    drivers/slimbus \
    drivers/ssb \
    drivers/soundwire \
    drivers/visorbus \
    sound \
    fs/btrfs \
    fs/xfs \
    fs/jfs \
    fs/reiserfs \
    fs/ocfs2 \
    fs/gfs2 \
    fs/nilfs2 \
    fs/udf \
    fs/hfs \
    fs/hfsplus \
    fs/affs \
    fs/jffs2 \
    fs/ubifs \
    fs/squashfs \
    fs/erofs \
    fs/exfat \
    fs/ntfs \
    fs/ntfs3 \
    fs/ceph \
    fs/cifs \
    fs/nfs \
    fs/nfsd \
    fs/lockd \
    fs/fscache \
    fs/cachefiles \
    fs/coda \
    fs/minix \
    fs/romfs \
    fs/sysv \
    fs/bfs \
    fs/9p \
    fs/fat ; do
    rm -rf "$MODBASE/$dir" 2>/dev/null || true
done

echo "=== Rebuilding module dependencies ==="
chroot "$ROOTFS" depmod -a "$KVER" 2>/dev/null || true

echo "=== Compressing kernel modules ==="
find "$ROOTFS/lib/modules" -name "*.ko" -exec gzip -9 {} \; 2>/dev/null || true

echo "=== Creating initramfs ==="
cd "$ROOTFS"
if [ ! -e init ]; then
    echo "ERROR: init file missing!"
    exit 1
fi
find . \( \
    -path './boot/*' -o \
    -path './var/cache/*' -o \
    -path './var/log/*' -o \
    -path './tmp/*' \
\) -prune -o -print0 | cpio --null --create --format=newc | gzip -9 > "$ISO_DIR/initramfs.img"
cd -

echo "=== Copying kernel ==="
cp "$ROOTFS"/boot/vmlinuz-* "$ISO_DIR/vmlinuz"

echo "=== Creating GRUB configuration ==="
mkdir -p "$ISO_DIR/boot/grub"
cat > "$ISO_DIR/boot/grub/grub.cfg" << 'EOF'
set timeout=0
set default=0
insmod all_video
insmod part_gpt
insmod part_msdos
insmod iso9660
search --no-floppy --set=root --file /vmlinuz
menuentry "lldpOS" {
    linux /vmlinuz rw quiet loglevel=3 modprobe.blacklist=nvme,nvme_core,ahci,libahci,sd_mod,sr_mod,usb_storage,uas,mmc_block,mmc_core,sdhci,sdhci_pci,floppy,virtio_blk,virtio_scsi,vmw_pvscsi,xen_blkfront,hv_storvsc,megaraid_sas,mpt3sas,mpt2sas,aacraid,hpsa,arcmsr,3w_9xxx,qla2xxx,lpfc
    initrd /initramfs.img
}
EOF

echo "=== Creating GRUB BIOS boot ==="
mkdir -p "$ISO_DIR/boot/grub/i386-pc"
cp -r /usr/lib/grub/i386-pc/*.mod "$ISO_DIR/boot/grub/i386-pc/" 2>/dev/null || true
cp -r /usr/lib/grub/i386-pc/*.lst "$ISO_DIR/boot/grub/i386-pc/" 2>/dev/null || true
cat > "$WORK_DIR/bios-embed.cfg" << 'EOF'
search --no-floppy --set=root --file /vmlinuz
configfile /boot/grub/grub.cfg
EOF
grub-mkimage --format=i386-pc --output="$ISO_DIR/boot/grub/core.img" --prefix="/boot/grub" --config="$WORK_DIR/bios-embed.cfg" biosdisk iso9660 part_msdos part_gpt normal search search_fs_file configfile linux
cat /usr/lib/grub/i386-pc/cdboot.img "$ISO_DIR/boot/grub/core.img" > "$ISO_DIR/boot/grub/bios.img"

echo "=== Creating GRUB EFI boot ==="
mkdir -p "$WORK_DIR/efi-temp/EFI/BOOT"
cat > "$WORK_DIR/efi-temp/EFI/BOOT/grub.cfg" << 'EOF'
set timeout=0
set default=0
insmod all_video
insmod part_gpt
insmod part_msdos
insmod iso9660
insmod search
insmod search_fs_file
search --no-floppy --set=root --file /vmlinuz
menuentry "lldpOS" {
    linux /vmlinuz rw quiet loglevel=3 modprobe.blacklist=nvme,nvme_core,ahci,libahci,sd_mod,sr_mod,usb_storage,uas,mmc_block,mmc_core,sdhci,sdhci_pci,floppy,virtio_blk,virtio_scsi,vmw_pvscsi,xen_blkfront,hv_storvsc,megaraid_sas,mpt3sas,mpt2sas,aacraid,hpsa,arcmsr,3w_9xxx,qla2xxx,lpfc
    initrd /initramfs.img
}
EOF
cat > "$WORK_DIR/efi-embed.cfg" << 'EOF'
search --no-floppy --set=root --file /vmlinuz
configfile /EFI/BOOT/grub.cfg
EOF
grub-mkimage --format=x86_64-efi --output="$WORK_DIR/efi-temp/EFI/BOOT/BOOTX64.EFI" --prefix="/EFI/BOOT" --config="$WORK_DIR/efi-embed.cfg" part_gpt part_msdos iso9660 fat normal linux search search_fs_file configfile all_video efi_gop efi_uga
dd if=/dev/zero of="$WORK_DIR/efi.img" bs=1M count=4
mkfs.vfat "$WORK_DIR/efi.img"
mkdir -p "$WORK_DIR/efi-mount"
mount -o loop "$WORK_DIR/efi.img" "$WORK_DIR/efi-mount"
cp -r "$WORK_DIR/efi-temp/EFI" "$WORK_DIR/efi-mount/"
umount "$WORK_DIR/efi-mount"
mkdir -p "$ISO_DIR/EFI/BOOT"
cp "$WORK_DIR/efi-temp/EFI/BOOT/BOOTX64.EFI" "$ISO_DIR/EFI/BOOT/"
cp "$WORK_DIR/efi-temp/EFI/BOOT/grub.cfg" "$ISO_DIR/EFI/BOOT/"

echo "=== Creating bootable ISO ==="
xorriso -as mkisofs -o "$OUTPUT_ISO" -b boot/grub/bios.img -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img -eltorito-alt-boot -e efi.img -no-emul-boot -isohybrid-gpt-basdat -V "LLDPOS" -graft-points "$ISO_DIR" /efi.img="$WORK_DIR/efi.img" 2>&1 | grep -v "WARNING"

VERSION=$(cat "$ROOTFS/etc/lldpos-version")
OUTPUT_ISO_VERSIONED="lldpOS-v${VERSION}.iso"
mv "$OUTPUT_ISO" "$OUTPUT_ISO_VERSIONED"

if [ -n "$HOST_UID" ] && [ -n "$HOST_GID" ]; then
    chown "$HOST_UID:$HOST_GID" "$OUTPUT_ISO_VERSIONED"
fi

echo "=== Build complete ==="
echo "ISO: $OUTPUT_ISO_VERSIONED ($(du -h $OUTPUT_ISO_VERSIONED | cut -f1))"

rm -rf "$WORK_DIR"
