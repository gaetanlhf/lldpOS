#!/bin/bash
export DIALOGRC=/dev/null
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
VERSION=$(cat /etc/lldpos-version 2>/dev/null || echo "unknown")

wait_for_lldpd() {
    local timeout=30
    while [ $timeout -gt 0 ]; do
        if lldpctl >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        ((timeout--))
    done
    return 1
}

init_interfaces() {
    for iface in /sys/class/net/*; do
        ifname=$(basename "$iface")
        [[ "$ifname" == "lo" ]] && continue
        ip link set "$ifname" up 2>/dev/null
    done
}

wait_for_lldp_data() {
    local max_attempts=15
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if lldpctl -f keyvalue 2>/dev/null | grep -q "\.chassis\.name="; then
            return 0
        fi
        sleep 1
        ((attempt++))
    done
    return 1
}

count_neighbors() {
    lldpctl -f keyvalue 2>/dev/null | grep -c "\.chassis\.name=" 2>/dev/null || echo "0"
}

get_local_iface_info() {
    local iface=$1
    local tmpfile=$2

    local mac speed duplex ips state

    mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null || echo "N/A")
    state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo "unknown")
    speed=$(ethtool "$iface" 2>/dev/null | awk '/Speed:/ {print $2}')
    duplex=$(ethtool "$iface" 2>/dev/null | awk '/Duplex:/ {print $2}')
    ips=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | tr '\n' ', ' | sed 's/,$//')

    echo "--- Local Interface ---" >> "$tmpfile"
    printf "  %-20s : %s\n" "Interface" "$iface" >> "$tmpfile"
    printf "  %-20s : %s\n" "State" "$state" >> "$tmpfile"
    printf "  %-20s : %s\n" "MAC" "$mac" >> "$tmpfile"
    [ -n "$speed" ] && printf "  %-20s : %s\n" "Speed" "$speed" >> "$tmpfile"
    [ -n "$duplex" ] && printf "  %-20s : %s\n" "Duplex" "$duplex" >> "$tmpfile"
    [ -n "$ips" ] && printf "  %-20s : %s\n" "IP(s)" "$ips" >> "$tmpfile"
    echo "" >> "$tmpfile"
}

show_neighbors() {
    local menu_items=()
    local local_ports=()
    local switch_names=()
    local switch_ports=()
    local i=1

    dialog --title "lldpOS v$VERSION" --infobox "Scanning LLDP neighbors..." 5 40
    sleep 1

    while IFS='|' read -r local_port switch_port switch_name; do
        [[ -z "$local_port" || -z "$switch_name" ]] && continue
        menu_items+=("$i" "$local_port: $switch_port on $switch_name")
        local_ports+=("$local_port")
        switch_names+=("$switch_name")
        switch_ports+=("$switch_port")
        ((i++))
    done < <(lldpctl -f keyvalue 2>/dev/null | awk -F= '
        /\.port\.ifname=/ {
            split($1, parts, ".")
            prefix = parts[2]
            switch_port[prefix] = $2
        }
        /\.chassis\.name=/ {
            split($1, parts, ".")
            prefix = parts[2]
            switch_name[prefix] = $2
        }
        END {
            for (key in switch_port) {
                if (switch_name[key] != "") {
                    print key "|" switch_port[key] "|" switch_name[key]
                }
            }
        }
    ')

    if [ ${#menu_items[@]} -eq 0 ]; then
        dialog --title "lldpOS v$VERSION" \
            --msgbox "No LLDP neighbors detected" 10 50
        return
    fi

    local choice
    choice=$(dialog --title "lldpOS v$VERSION" \
        --extra-button --extra-label "Refresh" \
        --menu "LLDP Neighbors:" 20 90 12 \
        "${menu_items[@]}" \
        3>&1 1>&2 2>&3)

    local ret=$?

    if [ $ret -eq 3 ]; then
        show_neighbors
        return
    fi

    if [ -n "$choice" ] && [ $ret -eq 0 ]; then
        local idx=$((choice - 1))
        show_neighbor_details "${local_ports[$idx]}" "${switch_names[$idx]}" "${switch_ports[$idx]}"
        show_neighbors
    fi
}

show_neighbor_details() {
    local local_port=$1
    local switch_name=$2
    local switch_port=$3
    local tmpfile=$(mktemp)

    dialog --title "lldpOS v$VERSION" --infobox "Loading LLDP details for $local_port..." 5 50

    get_local_iface_info "$local_port" "$tmpfile"

    local chassis_id chassis_descr chassis_mgmt
    local port_id port_descr port_ttl
    local sys_cap sys_cap_enabled
    local vlans=""

    while IFS='=' read -r key value; do
        [[ -z "$key" || -z "$value" ]] && continue
        [[ "$key" != lldp."$local_port".* ]] && continue

        case "$key" in
            *chassis.name)       chassis_name="$value" ;;
            *chassis.descr)      chassis_descr="$value" ;;
            *chassis.id)         chassis_id="$value" ;;
            *chassis.mgmt-ip*)   chassis_mgmt="${chassis_mgmt:+$chassis_mgmt, }$value" ;;
            *port.ifname)        port_id="$value" ;;
            *port.descr)         port_descr="$value" ;;
            *port.ttl)           port_ttl="$value" ;;
            *capability*enabled) sys_cap_enabled="${sys_cap_enabled:+$sys_cap_enabled, }$value" ;;
            *capability*type)    sys_cap="${sys_cap:+$sys_cap, }$value" ;;
            *vlan.vlan-id)       vlans="${vlans:+$vlans, }$value" ;;
            *vlan.pvid)          pvid="$value" ;;
        esac
    done < <(lldpctl -f keyvalue 2>/dev/null)

    echo "--- Remote Chassis ---" >> "$tmpfile"
    printf "  %-20s : %s\n" "Name" "$switch_name" >> "$tmpfile"
    [ -n "$chassis_id" ] && printf "  %-20s : %s\n" "Chassis ID" "$chassis_id" >> "$tmpfile"
    [ -n "$chassis_descr" ] && printf "  %-20s : %s\n" "Description" "$chassis_descr" >> "$tmpfile"
    [ -n "$chassis_mgmt" ] && printf "  %-20s : %s\n" "Management IP" "$chassis_mgmt" >> "$tmpfile"
    echo "" >> "$tmpfile"

    echo "--- Remote Port ---" >> "$tmpfile"
    printf "  %-20s : %s\n" "Port" "$switch_port" >> "$tmpfile"
    [ -n "$port_id" ] && [ "$port_id" != "$switch_port" ] && printf "  %-20s : %s\n" "Port ID" "$port_id" >> "$tmpfile"
    [ -n "$port_descr" ] && printf "  %-20s : %s\n" "Description" "$port_descr" >> "$tmpfile"
    [ -n "$port_ttl" ] && printf "  %-20s : %s\n" "TTL" "${port_ttl}s" >> "$tmpfile"
    echo "" >> "$tmpfile"

    if [ -n "$sys_cap" ] || [ -n "$sys_cap_enabled" ]; then
        echo "--- Capabilities ---" >> "$tmpfile"
        [ -n "$sys_cap" ] && printf "  %-20s : %s\n" "Available" "$sys_cap" >> "$tmpfile"
        [ -n "$sys_cap_enabled" ] && printf "  %-20s : %s\n" "Enabled" "$sys_cap_enabled" >> "$tmpfile"
        echo "" >> "$tmpfile"
    fi

    if [ -n "$vlans" ] || [ -n "$pvid" ]; then
        echo "--- VLAN ---" >> "$tmpfile"
        [ -n "$pvid" ] && printf "  %-20s : %s\n" "Native VLAN (PVID)" "$pvid" >> "$tmpfile"
        [ -n "$vlans" ] && printf "  %-20s : %s\n" "VLAN(s)" "$vlans" >> "$tmpfile"
        echo "" >> "$tmpfile"
    fi

    if [ ! -s "$tmpfile" ]; then
        dialog --title "lldpOS v$VERSION" \
            --msgbox "No LLDP information available for $local_port" 10 50
    else
        dialog --title "lldpOS v$VERSION" \
            --textbox "$tmpfile" 30 90
    fi

    rm -f "$tmpfile"
}

main_menu() {
    while true; do
        local nb
        nb=$(count_neighbors)
        local choice
        choice=$(dialog --title "lldpOS v$VERSION" \
            --no-cancel \
            --menu "Hostname: $(hostname)" \
            11 50 4 \
            1 "View LLDP Neighbors ($nb found)" \
            2 "Shell Access" \
            3 "Reboot System" \
            4 "Shutdown System" \
            3>&1 1>&2 2>&3)

        case $choice in
            1) show_neighbors ;;
            2)
                if [ ! -f /tmp/keyboard-configured ]; then
                    /usr/local/bin/keyconf
                    touch /tmp/keyboard-configured
                else
                    /usr/local/bin/shell-welcome
                fi
                /bin/bash
                ;;
            3)
                dialog --yesno "Reboot system now?" 7 40
                if [ $? -eq 0 ]; then
                    touch /run/lldpos-reboot
                    reboot
                fi
                ;;
            4)
                dialog --yesno "Shutdown system now?" 7 40
                [ $? -eq 0 ] && poweroff
                ;;
        esac
    done
}

if ! wait_for_lldpd; then
    dialog --title "lldpOS v$VERSION" --msgbox "LLDP daemon not available" 7 40
    sleep 5
    exit 1
fi

init_interfaces
wait_for_lldp_data

main_menu
