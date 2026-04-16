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

    echo "Local port: $local_port" >> "$tmpfile"
    echo "Switch: $switch_name" >> "$tmpfile"
    echo "Switch port: $switch_port" >> "$tmpfile"
    echo "" >> "$tmpfile"
    echo "Details:" >> "$tmpfile"

    while IFS='=' read -r key value; do
        [[ -z "$key" || -z "$value" ]] && continue
        if [[ "$key" == lldp.$local_port.* ]]; then
            local clean_key="${key#lldp.$local_port.}"
            clean_key="${clean_key//./ }"
            printf "%-30s : %s\n" "$clean_key" "$value" >> "$tmpfile"
        fi
    done < <(lldpctl -f keyvalue 2>/dev/null)

    if [ ! -s "$tmpfile" ]; then
        dialog --title "lldpOS v$VERSION" \
            --msgbox "No LLDP information available for $local_port" 10 50
    else
        dialog --title "lldpOS v$VERSION" \
            --textbox "$tmpfile" 40 130
    fi

    rm -f "$tmpfile"
}

main_menu() {
    while true; do
        local choice
        choice=$(dialog --title "lldpOS v$VERSION" \
            --no-cancel \
            --menu "Hostname: $(hostname)" \
            11 50 4 \
            1 "View LLDP Neighbors" \
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