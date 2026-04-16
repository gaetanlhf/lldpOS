<h2 align="center">lldpOS</h2>
<p align="center">A lightweight bootable Linux distribution for LLDP discovery and network diagnostics</p>
<p align="center">
    <a href="#about">About</a> •
    <a href="#features">Features</a> •
    <a href="#building">Building</a> •
    <a href="#usage">Usage</a> •
    <a href="#network-tools">Network Tools</a> •
    <a href="#license">License</a>
</p>

## About

lldpOS is a minimal, bootable Linux distribution designed for network engineers and system administrators. It provides an intuitive TUI interface for LLDP neighbor discovery and a comprehensive set of network diagnostic tools. Boot from ISO or USB and instantly access your network infrastructure information.

## Features

- ✅ **LLDP Discovery** with interactive TUI interface
- ✅ **Unique hostname generation** - automatically creates memorable hostnames (e.g., `brave-falcon-1234`) that are advertised via LLDP, making it easy to identify the server from switch CLI using `show lldp neighbors`
- ✅ **Comprehensive network tools** - ping, traceroute, tcpdump, iperf3, mtr, and more
- ✅ **Network configuration utilities** - DHCP, static IP, VLAN, bonding, bridging
- ✅ **BIOS and UEFI boot support** for maximum hardware compatibility
- ✅ **Small footprint** - minimal base system with essential networking packages
- ✅ **Firmware support** - includes drivers for common network adapters (Intel, Realtek, Broadcom, QLogic)
- ✅ **Interactive shell access** with built-in network configuration helpers
- ✅ **Live system** - runs entirely from RAM, no installation required

## Building

### Prerequisites

Building lldpOS requires a Debian-based system with the following packages:

```bash
sudo apt install wget xorriso grub-pc-bin grub-efi-amd64-bin grub-common mtools dosfstools cpio xz-utils
```

Alternatively, build inside Docker (see `docker-build.sh`) — no host packages required beyond Docker itself.

### Build Process

The build script creates a bootable ISO with all required components:

```bash
# Clone or download the repository
git clone <repository-url>
cd lldpOS

# Build the ISO
sudo ./build.sh
```

The build process will:
1. Fetch the Alpine Linux minirootfs and bootstrap it
2. Install networking tools and firmware via `apk`
3. Configure OpenRC services and `/etc/inittab` to launch the TUI on tty1
4. Create a compressed initramfs
5. Generate a hybrid BIOS/UEFI bootable ISO

The output will be `lldpOS-vYYYY.MM.DD.iso` with the build date as version.

### Required Files Structure

```
lldpOS/
├── build.sh
├── scripts/
│   ├── generate-hostname.sh
│   ├── shell-welcome
│   ├── welcome
│   ├── keyconf
│   ├── dns-config
│   ├── nethelp
│   ├── dhcp-config
│   ├── static-ip
│   ├── vlan-create
│   ├── bond-create
│   ├── bridge-create
│   └── lldp-display.sh
└── openrc/
    ├── generate-hostname
    └── inittab
```

## Usage

### Booting

lldpOS can be booted through multiple methods:

1. **USB Boot** (for physical hardware):
   ```bash
   sudo dd if=lldpOS-vYYYY.MM.DD.iso of=/dev/sdX bs=4M status=progress
   ```

2. **Remote Management Interface** (recommended for data centers):
   - **Dell iDRAC** - Virtual Console → Virtual Media → Map ISO
   - **HP iLO** - Virtual Media → Mount ISO/CDROM
   - **Supermicro IPMI** - Virtual Media → CD-ROM Image
   - **Lenovo XCC** - Remote Control → Virtual Media
   
   This allows you to boot lldpOS remotely without physical access, perfect for troubleshooting remote servers.

3. **Virtualization Platforms**:
   - VMware ESXi / vSphere - Mount as virtual CD/DVD
   - Proxmox VE - Upload ISO to storage, attach to VM
   - KVM/QEMU - Use `-cdrom` option
   - Hyper-V - Attach ISO to virtual DVD drive

4. **PXE Boot** (advanced):
   - Extract `vmlinuz` and `initramfs.img` from the ISO
   - Configure your PXE server to chainload these files

**Boot Process:**

Once booted, the system will automatically:
- Generate a unique hostname (e.g., `brave-falcon-1234`)
- Bring up all network interfaces
- Start LLDP daemon and discover neighbors
- Display the main TUI interface

### Main Interface

Upon boot, you'll see the main menu with four options:

```
┌─────────────────────────────────┐
│      lldpOS v2025.10.28         │
├─────────────────────────────────┤
│ Hostname: brave-falcon-1234     │
│                                 │
│ 1. View LLDP Neighbors          │
│ 2. Shell Access                 │
│ 3. Reboot System                │
│ 4. Shutdown System              │
└─────────────────────────────────┘
```

#### Navigation

- Use **arrow keys** or **number keys** to select options
- Press **Enter** to confirm
- In LLDP view, press **Refresh** button to rescan neighbors
- Select a neighbor to view detailed LLDP information

### Hostname Generation

lldpOS automatically generates a unique, memorable hostname on each boot using the format:
```
<adjective>-<animal>-<number>
```

Examples: `brave-falcon-1234`, `calm-leopard-5678`, `wise-eagle-9012`

**Why this matters for LLDP:**

This hostname is immediately advertised via LLDP to all connected switches. This means you can:

1. **Boot lldpOS** on a server
2. **Check from the switch** which port the server is connected to
3. **Identify the server** easily without needing to label cables or track MACs

This is particularly useful during:
- Rack and stack operations
- Cable verification in dense environments
- Troubleshooting in data centers
- Pre-deployment port mapping

### LLDP Discovery

The LLDP interface displays all discovered neighbors showing:
- Local interface name
- Remote switch/device name
- Remote port identification

Selecting a neighbor shows detailed information including:
- Chassis ID and description
- Port ID and description
- System capabilities
- Management addresses
- VLAN information (if available)

## Network Tools

### Shell Access

Press **2** from the main menu to access the shell.  
The first time you enter the shell, you'll be prompted to configure your keyboard layout.

### Available Commands

#### Network Configuration
- `nethelp` - Display comprehensive network configuration guide
- `dhcp-config` - Configure DHCP on an interface
- `static-ip` - Configure static IP address
- `vlan-create` - Create VLAN interface (802.1Q)
- `bond-create` - Create bonded interface (LACP/bonding)
- `bridge-create` - Create bridge interface
- `dns-config` - Configure DNS resolvers

#### Diagnostic Tools
- `ping` - ICMP echo requests
- `traceroute` - Trace network path to destination
- `mtr` - Combined ping and traceroute (interactive)
- `tcpdump` - Packet capture and analysis
- `iperf3` - Network bandwidth testing
- `ethtool` - Network interface configuration and statistics
- `dig` / `host` - DNS lookup tools
- `curl` / `wget` - HTTP/HTTPS requests

#### Network Information
- `ip` - Show/manipulate routing, devices, tunnels
- `ifconfig` - Configure network interfaces (legacy)
- `lldpctl` - Query LLDP daemon directly
- `ss` / `netstat` - Socket statistics

### Configuration Examples

**Configure DHCP:**
```bash
dhcp-config eno1
```

**Configure Static IP:**
```bash
static-ip eno1 192.168.1.100/24 192.168.1.1
```

**Create VLAN:**
```bash
vlan-create eno1 100  # Creates eno1.100
```

**Create Bond:**
```bash
bond-create bond0 eno1 eno2
```

**Create Bridge:**
```bash
bridge-create br0 eno1 eno2
```

**Configure DNS:**
```bash
dns-config 8.8.8.8 8.8.4.4
```

### Keyboard Configuration

If you need to reconfigure the keyboard layout:
```bash
keyconf
```

## Technical Details

### Base System
- **Distribution**: Alpine Linux (minirootfs)
- **Kernel**: `linux-lts` from Alpine repository
- **Init System**: OpenRC + busybox init
- **Shell**: bash

### Included Packages
- Network tools: `iproute2`, `net-tools`, `iputils`, `traceroute`, `mtr`, `tcpdump`, `ethtool`, `iperf3`
- DNS tools: `bind-tools`
- HTTP tools: `curl`, `wget`
- LLDP: `lldpd`
- Network configuration: `dhcpcd` (VLAN/bond/bridge via `iproute2`)
- Editors: `nano`, `less`
- Interface: `dialog` (for TUI)
- Keyboard: `kbd`, `kbd-bkeymaps`

### Firmware Support
- Realtek adapters
- Broadcom (bnx2, bnx2x)
- QLogic (qlogic + qed)
- Myricom
- Netronome

### Boot Process
1. GRUB loads kernel and initramfs
2. busybox init reads `/etc/inittab` and runs OpenRC sysinit/boot/default
3. `generate-hostname` OpenRC service creates a unique hostname
4. Network interfaces are brought up automatically
5. `lldpd` starts and begins neighbor discovery
6. `inittab` respawns the main TUI on tty1

### System Characteristics
- **Read-only root**: Entire system runs from RAM
- **No persistence**: All changes are lost on reboot
- **Stateless**: Perfect for diagnostic purposes
- **Secure**: No passwords, no open services by default

## Use Cases

lldpOS is designed for:

- **Data center diagnostics** - Quick LLDP verification during rack and stack
- **Network troubleshooting** - Boot from USB to diagnose connectivity issues
- **Infrastructure mapping** - Discover network topology without configuration
- **Pre-deployment testing** - Verify cabling and switch configuration before OS installation
- **Training and labs** - Consistent network diagnostic environment
- **Emergency recovery** - Network access when the installed OS is unavailable

## License

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.