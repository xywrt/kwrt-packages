#!/bin/bash

export LC_ALL=C
export LANG=C

detect_terminal_mode() {
    terminal_width=$(stty size 2>/dev/null | awk '{print $2}' || echo "80")
    terminal_height=$(stty size 2>/dev/null | awk '{print $1}' || echo "24")
    
    if [ "$terminal_width" -lt 80 ]; then
        MODE="mobile"
    else
        MODE="desktop"
    fi
}

linux_logo="
                   _
|\     /||\     /|( )
( \   / )( \   / )| |
 \ (_) /  \ (_) / | |
  ) _ (    \   /  | |
 / ( ) \    ) (   (_)
( /   \ )   | |    _
|/     \|   \_/   (_)

"

format_memory() {
    local kb_value="$1"
    local mb_value=$((kb_value / 1024))
    
    if [ "$mb_value" -ge 1000 ]; then
        local gb_value=$(awk "BEGIN {printf \"%.1f\", $mb_value/1000}")
        echo "${gb_value}GB"
    else
        echo "${mb_value}MB"
    fi
}

format_storage() {
    local kb_value="$1"
    local mb_value=$((kb_value / 1024))
    
    if [ "$mb_value" -ge 1000 ]; then
        local gb_value=$(awk "BEGIN {printf \"%.1f\", $mb_value/1000}")
        echo "${gb_value}GB"
    else
        echo "${mb_value}MB"
    fi
}

get_active_interface_info() {
    printf "\033[1;33m"
    
    interface_count=0
    temp_file="/tmp/interfaces_list_$$"
    
    # Create unique list of interfaces with IP addresses
    > "$temp_file"
    
    # Method: Get interfaces from /sys/class/net and check for IP
    for iface in $(ls /sys/class/net/ 2>/dev/null); do
        # Skip loopback interface
        if [ "$iface" = "lo" ]; then
            continue
        fi
        
        # Filter out unwanted interfaces (only exclude specific ones)
        case "$iface" in
            utun*|tun*|tap*|virbr*|docker*|veth*)
                continue
                ;;
            br-*)
                # Allow br-lan but exclude other br- interfaces except common ones
                case "$iface" in
                    br-lan|br-wan)
                        ;;
                    *)
                        continue
                        ;;
                esac
                ;;
        esac
        
        # Get IP address for this interface
        ip_addr=$(ip addr show "$iface" 2>/dev/null | awk '/inet / && !/127\.0\.0\.1/ {print $2; exit}' | cut -d'/' -f1)
        
        if [ -n "$ip_addr" ]; then
            # Check if this interface is not already in the list
            if ! grep -q "^$iface " "$temp_file" 2>/dev/null; then
                echo "$iface $ip_addr" >> "$temp_file"
            fi
        fi
    done
    
    # Display up to 6 interfaces
    while read -r interface ip_addr && [ $interface_count -lt 6 ]; do
        if [ -n "$interface" ] && [ -n "$ip_addr" ]; then
            printf "%-10s: %s\n" "$interface" "$ip_addr"
            interface_count=$((interface_count + 1))
        fi
    done < "$temp_file"
    
    # Clean up
    rm -f "$temp_file"
    
    # If no interfaces found
    if [ $interface_count -eq 0 ]; then
        printf "%-10s: %s\n" "N/A" "N/A"
    fi
    
    printf "\033[0m"
}

get_system_info() {
    os=$(grep 'DISTRIB_DESCRIPTION' /etc/openwrt_release | cut -d "'" -f 2 2>/dev/null || echo "Unknown Linux")
    [ -z "$os" ] && os="Unknown Linux"
    
    host=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || hostname 2>/dev/null || echo "Unknown")
    [ -z "$host" ] && host="Unknown"
    
    kernel=$(uname -r 2>/dev/null || echo "Unknown")
    [ -z "$kernel" ] && kernel="Unknown"
    

    if [ -e /proc/cpuinfo ]; then
        local CPU_Arch=$(awk '/CPU architecture/ {print $3; exit}' /proc/cpuinfo)
        local CPU_Part=$(awk '/CPU part/ {print $4; exit}' /proc/cpuinfo)
        local CPU_Variant=$(awk '/CPU variant/ {print $3; exit}' /proc/cpuinfo)
        local CPU_Implementer=$(awk '/CPU implementer/ {print $3; exit}' /proc/cpuinfo)
        CPU_Info="ARMv${CPU_Arch} Processor rev ${CPU_Variant} (v${CPU_Implementer}l)"
    fi


    cpu_model=$CPU_Info 2>/dev/null || echo "Unknown"
    [ -z "$cpu_model" ] && cpu_model="Unknown"
    
    uptime=$(awk '{
        days=int($1/86400)
        hours=int($1%86400/3600)
        minutes=int(($1%3600)/60)
        if(days>0) printf "%d days, %d hours", days, hours
        else if(hours>0) printf "%d hours, %d minutes", hours, minutes
        else printf "%d minutes", minutes
    }' /proc/uptime 2>/dev/null || echo "Unknown")
    [ -z "$uptime" ] && uptime="Unknown"
    
    cpu_temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | awk '{printf "%.0f°C\n", $1/1000; exit}' || echo "N/A")
    [ -z "$cpu_temp" ] && cpu_temp="N/A"
    
    mem_info="Unknown"
    if [ -f /proc/meminfo ]; then
        mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null)
        mem_available_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null)
        
        if [ -z "$mem_available_kb" ]; then
            mem_free_kb=$(awk '/MemFree/ {print $2}' /proc/meminfo 2>/dev/null)
            mem_cached_kb=$(awk '/Cached/ {print $2}' /proc/meminfo 2>/dev/null)
            mem_available_kb=$((mem_free_kb + mem_cached_kb))
        fi
        
        if [ -n "$mem_total_kb" ] && [ "$mem_total_kb" -gt 0 ] 2>/dev/null; then
            mem_used_kb=$((mem_total_kb - mem_available_kb))
            mem_percent=$(awk "BEGIN {printf \"%.0f\", ($mem_used_kb/$mem_total_kb*100)}")
            mem_used_formatted=$(format_memory "$mem_used_kb")
            mem_total_formatted=$(format_memory "$mem_total_kb")
            mem_info="${mem_used_formatted}/${mem_total_formatted} (${mem_percent}%)"
        fi
    fi
    
    rootfs_info="Unknown"
    if command -v df >/dev/null 2>&1; then
        rootfs_data=$(df / 2>/dev/null | tail -n 1)
        if [ -n "$rootfs_data" ]; then
            rootfs_total_kb=$(echo "$rootfs_data" | awk '{print $2}')
            rootfs_used_kb=$(echo "$rootfs_data" | awk '{print $3}')
            rootfs_available_kb=$(echo "$rootfs_data" | awk '{print $4}')
            rootfs_percent=$(echo "$rootfs_data" | awk '{print $5}' | tr -d '%')
            
            if [ -n "$rootfs_total_kb" ] && [ "$rootfs_total_kb" -gt 0 ] 2>/dev/null; then
                rootfs_used_formatted=$(format_storage "$rootfs_used_kb")
                rootfs_total_formatted=$(format_storage "$rootfs_total_kb")
                rootfs_info="${rootfs_used_formatted}/${rootfs_total_formatted} (${rootfs_percent}%)"
            fi
        fi
    fi
}

display_logo() {
    printf "\033[1;34m"
    for i in {1..65}; do printf "="; done
    printf "\033[0m\n"
    
    # Center the logo
    printf "\033[1;32m"
    echo "$linux_logo" | while IFS= read -r line; do
        logo_width=$(echo "$line" | wc -c)
        logo_width=$((logo_width - 1))
        pad=$(( (65 - logo_width) / 2 ))
        printf "%*s%s\n" $pad "" "$line"
    done
    printf "\033[0m"
}

display_text_info() {
    printf "\033[1;34m"
    for i in {1..65}; do printf "="; done
    printf "\033[0m\n"
    
    info_text="by xybydy"
    pad=$(( (65 - ${#info_text}) / 2 ))
    printf "\033[1;33m%*s%s%*s\033[0m\n" $pad "" "$info_text" $pad ""
}

display_system_info() {
    get_system_info
    
    echo
    printf "\033[1;36m"
    echo "OS        : $os | $host"
    echo "CPU       : $cpu_model | $cpu_temp"
    echo "Kernel    : $kernel"
    printf "\033[1;32m"
    echo "RootFS    : $rootfs_info"
    printf "\033[1;36m"
    echo "Memory    : $mem_info"
    echo "Uptime    : $uptime"
    get_active_interface_info
    echo
}

main_display() {
    detect_terminal_mode
    clear
    
    display_logo
    display_text_info
    display_system_info
}

main_display