#!/bin/bash

# shellcheck disable=SC1009
# shellcheck disable=SC2155
# shellcheck disable=SC2092
# shellcheck disable=SC2006
# shellcheck disable=SC2207

# colors
export red="$(tput setaf 1)"
export green="$(tput setaf 2)"
export yellow="$(tput setaf 3)"
export blue="$(tput setaf 4)"
export orange="$(tput setaf 208)"
export light_cyan="$(tput setaf 51)"

check_packages() {
    if command -v curl &>/dev/null && command -v mpstat &>/dev/null; then
        echo " "
    else
        sudo apt-get install curl -yy && sudo apt-get install mpstat -yy
    fi
}

check_packages

notifications() {
    local message="$1"    
    bot_token=""
    USER_CHAT_ID=""
    TELEGRAM_API_URL="https://api.telegram.org/bot$bot_token/sendMessage"
    curl -X POST $TELEGRAM_API_URL -d chat_id=$USER_CHAT_ID -d text="$message" &>/dev/null # redirect both stdout and stderr
}


metrics() {
    current_time_fixed=$(date "+%m-%d %H:%M:%S")

    ram_left() {
        local var_name="$1"
        local var_value="${!var_name}"

        var_value="${var_value//[^0-9]/}"

        local total_ram=$(free -m | awk 'NR==2{print $2}')

        # less than 50% left
        if [ "$var_value" -gt "$((total_ram / 2))" ]; then
            eval "$var_name=\"$red\$var_value\""
            notification_message="🔴[$current_time_fixed] Less than 50% Ram Left"
            notifications "$notification_message"
        fi

        # total ram 75% left
        if [ "$var_value" -gt "$((total_ram * 75 / 100))" ]; then
            eval "$var_name=\"$red\$var_value\""

        elif [ "$var_value" -lt "$((total_ram * 50 / 100))" ]; then
            eval "$var_name=\"$green\$var_value\""
        fi
    }

    storage_used() {
        local var_name="$1"
        local var_value="${!var_name}"

        var_value="${var_value//[^0-9]/}"

        if [ "$var_value" -gt "$((var_value / 2))" ]; then
            eval "$var_name=\"$red\$var_value\""
            # 50% left
        fi

        if [ "$var_value" -gt "$((var_value * 75 / 100))" ]; then
            eval "$var_name=\"$red\$var_value\""
            # 75% left

        elif [ "$var_value" -lt "$((var_value * 50 / 100))" ]; then
            eval "$var_name=\"$green\$var_value\""
            # 25% left

            notification_message="🔴[$current_time_fixed] 25% of storage left ."
            notifications "$notification_message"
        fi
    }

    colorize_left() {
        local var_name="$1"
        local var_value="${!var_name}"

        # Extract resource name from var_name (remaining_ram or remaining_storage)
        local resource_name="${var_name#remaining_}"

        var_value="${var_value//[^0-9]/}"

        # Current time with seconds
        local current_time="$(date '+%Y-%m-%d %H:%M:%S')"

        # Check resource usage and colorize
        if [ "$var_value" -lt "$((var_value / 4))" ]; then
            eval "$var_name=\"$red\$var_value\""

            notification_message="🔴[$current_time_fixed] $resource_name: Less than 25% left."
            notifications "$notification_message"

        elif [ "$var_value" -lt "$((var_value / 2))" ]; then
            eval "$var_name=\"$orange\$var_value\""

            notification_message="🟠[$current_time_fixed] $resource_name: Less than 50% left."
            notifications "$notification_message"

        elif [ "$var_value" -ge "$((var_value / 2))" ]; then
            eval "$var_name=\"$green\$var_value\""
        fi
    }

    while true; do
        # Variables here

        # uptime
        uptime_seconds=$(awk '{print int($1)}' /proc/uptime)

        uptime_days=$((uptime_seconds / 86400))
        uptime_hours=$((uptime_seconds % 86400 / 3600))
        uptime_minutes=$((uptime_seconds % 3600 / 60))
        uptime_seconds=$((uptime_seconds % 60))

        if [ "$uptime_days" -gt 0 ]; then
            show_uptime="$uptime_days day(s), $uptime_hours hour(s), $uptime_minutes minute(s), $uptime_seconds second(s)"
        elif [ "$uptime_hours" -gt 0 ]; then
            show_uptime="$uptime_hours hour(s), $uptime_minutes minute(s), $uptime_seconds second(s)"
        elif [ "$uptime_minutes" -gt 0 ]; then
            show_uptime="$uptime_minutes minute(s), $uptime_seconds second(s)"
        else
            show_uptime="$uptime_seconds second(s)"
        fi

        # hostname
        hostname=$(hostname)

        # cpus
        num_cores=$(nproc)

        get_cpu_usage() {
            local core_usage
            core_usage=$(mpstat -P "$1" 1 1 | awk 'NR == 4 {print int($4)}')
            if [ "$core_usage" -gt 100 ]; then
                core_usage=100
            fi
            echo "$core_usage"
        }

        cpu_usages=()

        for ((core = 0; core < num_cores; core++)); do
            core_usage=$(get_cpu_usage "$core")

            color=""

            # Calculate the time difference since the last noti
            current_time=$(date +%s)
            time_diff=$((current_time - last_notification_time))

            # Check CPU usage and colorize
            if [ "$core_usage" -gt 75 ] && [ "$time_diff" -ge 10 ]; then
                color="$red" # red

                core_number=$((core + 1))
                notification_message="🔴[$current_time_fixed] High Cpu usage on Core $core_number"
                notifications "$notification_message"

                # Update
                last_notification_time=$current_time

            elif [ "$core_usage" -gt 50 ]; then
                color="$orange" # orange
            elif [ "$core_usage" -gt 25 ]; then
                color="$green" # green
            else
                color="$light_cyan" # light_cyan
            fi

            cpu_usages+=("CPU $((core + 1)): ${color}${core_usage}%$blue")
        done

        cpu_usage_line=$(
            IFS=' | '
            echo "${cpu_usages[*]}"
        )

        # processor
        processor=$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo)

        if [[ "$processor" == *"AMD"* ]]; then
            processor="$orange $processor"

        elif [[ "$processor" == *"Intel"* ]]; then
            processor="$light_cyan $processor"
        fi

        # Get RAM information
        total_ram=$(free -m | awk 'NR==2{print $2}')
        used_ram=$(free -m | awk 'NR==2{print $3}')
        remaining_ram=$((total_ram - used_ram))

        ram_left "used_ram"

        disk_info=$(df -h --total | tail -n 1)
        total_storage=$(echo "$disk_info" | awk '{print $2}')
        used_storage=$(echo "$disk_info" | awk '{print $3}')
        remaining_storage=$(echo "$disk_info" | awk '{print $4}')

        storage_used "used_storage"

        # who
        who=$(whoami)

        colorize_left "remaining_ram"
        colorize_left "remaining_storage"

        clear

        # Interface
        echo "$blue              @@               Hostname: $hostname | $who"
        echo "$blue          @@@@@@ @@            Ram: $used_ram$blue/$total_ram MB | Available: $remaining_ram"
        echo "$blue         @@@@@@@ @@@@          Storage: $used_storage$blue/$total_storage | Available : $remaining_storage"
        echo "$blue      @@@@@@@@  *@@@@@@@       Processor:$processor"
        echo "$blue     @@@@@@@@  @@@@@@@@@@      CPUs: $num_cores"
        echo "$blue   @@@@@@@@     @@@@@@@@@@@    Usage: $cpu_usage_line"
        echo "$blue  @@@@@@@@        @@@@@@@@@@   Uptime: $show_uptime"

        sleep 0.5

    done
}

metrics
