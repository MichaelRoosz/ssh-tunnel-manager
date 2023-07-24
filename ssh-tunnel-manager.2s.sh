#!/bin/zsh

export PATH="/opt/homebrew/bin:$PATH"
export SSH_ASKPASS=/opt/homebrew/bin/ssh-askpass
export SSH_ASKPASS_REQUIRE=force

current_script=$(realpath "$0")

config_dir="$HOME/ssh-tunnels"

ssh_arguments="24afxNT"

start_tunnel() {
    local config_file="$1"
    local tunnel_name="$2"
    local tunnel_data

    # Load config data from the specified file and tunnel
    tunnel_data=$(jq -r ".\"$tunnel_name\"" "$config_file")
    local host=$(echo "$tunnel_data" | jq -r '.host')
    local user=$(echo "$tunnel_data" | jq -r '.user')
    local port=$(echo "$tunnel_data" | jq -r '.port')
    local identity=$(echo "$tunnel_data" | jq -r '.identity')
    local tunnel_type=$(echo "$tunnel_data" | jq -r '.tunnel_type')
    local autoconnect=$(echo "$tunnel_data" | jq -r '.autoconnect')
    local localport=$(echo "$tunnel_data" | jq -r '.localport')
    local options=$(echo "$tunnel_data" | jq -r '.options[]')

    local options_array=()
    while IFS= read -r line; do
        options_array+=("$line")
    done <<< "$options"

    # Check if it's a dynamic (SOCKS) or normal tunnel
    if [ "$tunnel_type" = "socks" ]; then
        ssh -${ssh_arguments}D "localhost:$localport" -i "$identity" -p "$port" "$user"@"$host" -o ExitOnForwardFailure=yes "${options_array[@]}"
    else
        local remotehost=$(echo "$tunnel_data" | jq -r '.remotehost')
        local remoteport=$(echo "$tunnel_data" | jq -r '.remoteport')
        ssh -${ssh_arguments}L "localhost:$localport:$remotehost:$remoteport" -i "$identity" -p "$port" "$user"@"$host" -o ExitOnForwardFailure=yes "${options_array[@]}"
    fi

    jq -r "(.\"$tunnel_name\").stopped = false" "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
}

stop_tunnel() {
    local config_file="$1"
    local tunnel_name="$2"

    local localport=$(jq -r ".\"$tunnel_name\".localport" "$config_file")
    pkill -f "ssh.*-${ssh_arguments}[LD] localhost:${localport}[ :].*ExitOnForwardFailure=yes.*"

    jq -r "(.\"$tunnel_name\").stopped = true" "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
}

stop_all_tunnels() {
    local config_files=("$config_dir"/*.json)

    for config_file in "${config_files[@]}"; do
        local tunnels=($(jq -r 'keys[]' "$config_file"))

        for tunnel_name in "${tunnels[@]}"; do
            stop_tunnel $config_file $tunnel_name
        done
    done
}

tunnel_info() {
    local config_file="$1"
    local tunnel_name="$2"
    local tunnel_data

    # Load config data from the specified file and tunnel
    tunnel_data=$(jq -r ".\"$tunnel_name\"" "$config_file")
    local host=$(echo "$tunnel_data" | jq -r '.host')
    local user=$(echo "$tunnel_data" | jq -r '.user')
    local port=$(echo "$tunnel_data" | jq -r '.port')
    local identity=$(echo "$tunnel_data" | jq -r '.identity')
    local tunnel_type=$(echo "$tunnel_data" | jq -r '.tunnel_type')
    local localport=$(echo "$tunnel_data" | jq -r '.localport')
    local options=$(echo "$tunnel_data" | jq -r '.options | join(" ")')

    # Create the dialog content
    local dialog_content="Tunnel Info: $tunnel_name\n\nType: $tunnel_type\nHost: $host\nUser: $user\nPort: $port\nLocal Port: $localport\nIdentity: $identity\nOptions: $options"

    # Show the dialog window using osascript
    osascript -e "display dialog \"$dialog_content\" with icon note with title \"SSH Tunnel Info\" buttons {\"OK\"} default button \"OK\""
}

toggle_autoconnect() {
    local config_file="$1"
    local tunnel_name="$2"
    local autoconnect

    # Load current autoconnect value
    autoconnect=$(jq -r ".\"$tunnel_name\".autoconnect" "$config_file")
    
    # Toggle the value
    if [ "$autoconnect" = "true" ]; then
        autoconnect="false"
    else
        autoconnect="true"
    fi

    # Update the config file with the new value
    jq -r "(.\"$tunnel_name\").autoconnect = $autoconnect" "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
}

# Function to display the menu in xbar
xbar_menu() {
    local config_files=("$config_dir"/*.json)

    echo "SSH Tunnels"
    echo "---"

    for config_file in "${config_files[@]}"; do
        local tunnels=($(jq -r 'keys[]' "$config_file"))

        for tunnel_name in "${tunnels[@]}"; do
            local tunnel_data

            # Load config data from the specified file and tunnel
            tunnel_data=$(jq -r ".\"$tunnel_name\"" "$config_file")
            local tunnel_status="🔴"   # Emoji: Red circle for offline tunnel

            local localport=$(echo "$tunnel_data" | jq -r '.localport')

            if pgrep -f "ssh.*-${ssh_arguments}[LD] localhost:${localport}[ :].*ExitOnForwardFailure=yes.*" > /dev/null; then
                tunnel_status="🟢"   # Emoji: Green circle for running tunnel
            fi

            local connection_status="Connect"  # Default status
            local connection_action="start"

            if [ "$tunnel_status" = "🟢" ]; then
                connection_status="Disconnect"
                connection_action="stop"
            fi

            local autoconnect_status

            # Load current autoconnect value
            local autoconnect=$(echo "$tunnel_data" | jq -r '.autoconnect')
            local stopped=$(echo "$tunnel_data" | jq -r '.stopped')

            # Toggle the value
            if [ "$autoconnect" = "true" ]; then
                autoconnect_status="on"

                if [ "$connection_action" = "start" ] && [ "$stopped" != "true" ]; then
                    start_tunnel $config_file $tunnel_name
                fi
            else
                autoconnect_status="off"
            fi

            echo "$tunnel_name $tunnel_status | bash='$current_script' param1=$connection_action param2=$config_file param3=$tunnel_name terminal=false refresh=true"
            echo "-- $connection_status | bash='$current_script' param1=$connection_action param2=$config_file param3=$tunnel_name terminal=false refresh=true"
            echo "-- Auto reconnect $autoconnect_status | bash='$current_script' param1=toggle_autoconnect param2=$config_file param3=$tunnel_name terminal=false refresh=true"
            echo "-- Info | bash='$current_script' param1=tunnel_info param2=$config_file param3=$tunnel_name terminal=false"
        done
    done

    echo "---"
    echo "Disconnect All | bash='$current_script' param1=stop_all terminal=false"
}

# Main function
main() {
    local action="$1"

    case "$action" in
        start)
            local config_file="$2"
            local tunnel_name="$3"
            start_tunnel "$config_file" "$tunnel_name"
            ;;
        stop)
            local config_file="$2"
            local tunnel_name="$3"
            stop_tunnel "$config_file" "$tunnel_name"
            ;;
        stop_all)
            stop_all_tunnels
            ;;
        tunnel_info)
            local config_file="$2"
            local tunnel_name="$3"
            tunnel_info "$config_file" "$tunnel_name"
            ;;
        toggle_autoconnect)
            local config_file="$2"
            local tunnel_name="$3"
            toggle_autoconnect "$config_file" "$tunnel_name"
            ;;
        *)
            xbar_menu
            ;;
    esac
}

# Execute main function
main "$@"
