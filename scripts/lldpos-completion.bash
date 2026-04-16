_lldpos_ifaces() {
    local ifaces
    ifaces=$(ls /sys/class/net/ 2>/dev/null | grep -v lo)
    COMPREPLY=($(compgen -W "$ifaces" -- "${COMP_WORDS[COMP_CWORD]}"))
}

_lldpos_bond_modes() {
    local modes="balance-rr active-backup balance-xor broadcast 802.3ad balance-tlb balance-alb 0 1 2 3 4 5 6"
    case $COMP_CWORD in
        1) COMPREPLY=($(compgen -W "bond0 bond1 bond2" -- "${COMP_WORDS[COMP_CWORD]}")) ;;
        2) COMPREPLY=($(compgen -W "$modes" -- "${COMP_WORDS[COMP_CWORD]}")) ;;
        *) _lldpos_ifaces ;;
    esac
}

_lldpos_bridge() {
    case $COMP_CWORD in
        1) COMPREPLY=($(compgen -W "br0 br1 br2" -- "${COMP_WORDS[COMP_CWORD]}")) ;;
        *) _lldpos_ifaces ;;
    esac
}

_lldpos_vlan() {
    case $COMP_CWORD in
        1) _lldpos_ifaces ;;
        2) COMPREPLY=($(compgen -W "100 200 300 400 500" -- "${COMP_WORDS[COMP_CWORD]}")) ;;
    esac
}

_lldpos_dns() {
    local servers="8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1 9.9.9.9 149.112.112.112 208.67.222.222 208.67.220.220"
    COMPREPLY=($(compgen -W "$servers" -- "${COMP_WORDS[COMP_CWORD]}"))
}

complete -F _lldpos_ifaces dhcp-config
complete -F _lldpos_ifaces static-ip
complete -F _lldpos_ifaces iface-reset
complete -F _lldpos_ifaces ethtool
complete -F _lldpos_vlan vlan-create
complete -F _lldpos_bond_modes bond-create
complete -F _lldpos_bridge bridge-create
complete -F _lldpos_dns dns-config
