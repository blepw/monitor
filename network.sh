#!/bin/bash


connections() {
    local valid_ip_pattern="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    declare -A known_connections

    max_ip_length=0
    while read -r ip; do
        if [[ $ip =~ $valid_ip_pattern ]]; then
            ip_length=${#ip}
            if ((ip_length > max_ip_length)); then
                max_ip_length=$ip_length
            fi
        fi
    done < <(netstat -n | awk '/^tcp/ {print $5}' | cut -d: -f1 | sort -u)

    header_spaces=" "
    for ((i = 0; i < max_ip_length; i++)); do
        header_spaces+=" "
    done

    echo "IP${header_spaces}ORG${header_spaces}COUNTRY${header_spaces}REGION"

    while true; do
        local active_connections
        active_connections=$(netstat -n | awk '/^tcp/ {print $5}' | cut -d: -f1 | sort -u)

        for ip in $active_connections; do
            if [[ $ip =~ $valid_ip_pattern ]] && [ -z "${known_connections[$ip]}" ]; then
                info=$(curl -s "https://ipinfo.io/$ip" | jq -r '.ip, .org, .country, .city, .region' | tr '\n' ' ')
                echo "$info"
                known_connections[$ip]=1
            fi
        done

        sleep 2
    done
}

# clear screen
clear 

connections 
