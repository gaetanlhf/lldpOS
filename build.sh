#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
SYSTEMD_DIR="$SCRIPT_DIR/systemd"

for cmd in debootstrap xorriso grub-mkimage cpio; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd not found"
        echo "Install: apt install debootstrap xorriso grub-pc grub-efi-amd64-bin dosfstools cpio"
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
)

REQUIRED_SYSTEMD=(
    "generate-hostname.service"
    "lldp-display.service"
    "getty@tty1-override.conf"
)

MISSING=0

for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ ! -f "$SCRIPTS_DIR/$script" ]; then
        echo "Error: Missing script: scripts/$script"
        MISSING=1
    fi
done

for unit in "${REQUIRED_SYSTEMD[@]}"; do
    if [ ! -f "$SYSTEMD_DIR/$unit" ]; then
        echo "Error: Missing systemd file: systemd/$unit"
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

echo "=== Installing base system ==="
debootstrap --variant=minbase \
    --include=linux-image-amd64,firmware-linux,firmware-misc-nonfree,firmware-realtek,firmware-bnx2,firmware-bnx2x,firmware-netxen,firmware-qlogic,firmware-myricom,firmware-netronome,lldpd,systemd-sysv,dialog,iputils-ping,bind9-dnsutils,bind9-host,tcpdump,curl,wget,iproute2,net-tools,traceroute,ethtool,iperf3,mtr-tiny,kbd,console-data,dhcpcd5,bridge-utils,vlan,less,nano \
    --components=main,non-free-firmware,non-free,contrib \
    stable "$ROOTFS" http://deb.debian.org/debian

echo "=== Installing scripts ==="
mkdir -p "$ROOTFS/usr/local/bin"
cp "$SCRIPTS_DIR"/* "$ROOTFS/usr/local/bin/"
chmod +x "$ROOTFS/usr/local/bin"/*

echo "=== Installing init script ==="
cat > "$ROOTFS/init" << 'EOFINIT'
#!/bin/sh
exec /usr/lib/systemd/systemd
EOFINIT
chmod +x "$ROOTFS/init"

echo "=== Installing systemd units ==="
mkdir -p "$ROOTFS/etc/systemd/system"
mkdir -p "$ROOTFS/etc/systemd/system/getty@tty1.service.d"
cp "$SYSTEMD_DIR/generate-hostname.service" "$ROOTFS/etc/systemd/system/"
cp "$SYSTEMD_DIR/lldp-display.service" "$ROOTFS/etc/systemd/system/"
cp "$SYSTEMD_DIR/getty@tty1-override.conf" "$ROOTFS/etc/systemd/system/getty@tty1.service.d/override.conf"

echo "=== Creating version file ==="
date '+%Y.%m.%d' > "$ROOTFS/etc/lldpos-version"

for i in {2..6}; do
    chroot "$ROOTFS" systemctl mask getty@tty$i.service
done
chroot "$ROOTFS" systemctl mask serial-getty@ttyS0.service

echo "=== Configuring services ==="
chroot "$ROOTFS" /bin/bash << 'CHROOT'
systemctl enable generate-hostname
systemctl enable lldpd
systemctl enable lldp-display
systemctl set-default multi-user.target
passwd -d root
CHROOT

echo "=== Clean apt ==="
chroot "$ROOTFS" apt-get clean

echo "=== Removing non-English locales ==="
find "$ROOTFS/usr/share/locale" -mindepth 1 -maxdepth 1 ! -name 'en*' -exec rm -rf {} + 2>/dev/null || true
find "$ROOTFS/usr/share/i18n/locales" -mindepth 1 -maxdepth 1 ! -name 'en*' -exec rm -rf {} + 2>/dev/null || true

echo "=== Removing kernel headers and sources ==="
rm -rf "$ROOTFS/usr/src"/*
rm -rf "$ROOTFS/lib/modules"/*/build
rm -rf "$ROOTFS/lib/modules"/*/source

echo "=== Compressing kernel modules ==="
find "$ROOTFS/lib/modules" -name "*.ko" -exec xz -9 --check=crc32 {} \; 2>/dev/null || true

echo "=== Package manager cleanup ==="
rm -rf "$ROOTFS/var/lib/dpkg/info"/*
rm -rf "$ROOTFS/var/cache/debconf"/*

echo "=== Removing Python cache ==="
find "$ROOTFS" -type f -name "*.pyc" -delete 2>/dev/null || true
find "$ROOTFS" -type f -name "*.pyo" -delete 2>/dev/null || true
find "$ROOTFS" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

echo "=== Removing test files ==="
find "$ROOTFS" -type d -name "test" -path "*/lib/*" -exec rm -rf {} + 2>/dev/null || true
find "$ROOTFS" -type d -name "tests" -path "*/lib/*" -exec rm -rf {} + 2>/dev/null || true

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
\) -prune -o -print0 | cpio --null --create --format=newc | xz -9e --check=crc32 -T8 > "$ISO_DIR/initramfs.img"
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
    linux /vmlinuz rw quiet
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
    linux /vmlinuz rw quiet
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

echo "=== Build complete ==="
echo "ISO: $OUTPUT_ISO_VERSIONED ($(du -h $OUTPUT_ISO_VERSIONED | cut -f1))"

rm -rf "$WORK_DIR"