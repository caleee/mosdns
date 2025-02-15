#!/bin/sh
#
# Filename: mosdns-data_update.sh
# Author: Cao Lei <caolei@mail.com>
# Version: 1.0.0 - 1.0.1
# Date: 2024/02/14 - 2024/02/15
# License: Apache 2.0
# Description: This script is used to initialize and update mosdns configuration and data
# Usage: Run this script as root: chmod +x mosdns-data_update.sh && sh mosdns-data_update.sh
# For crontab(root): 0 3 * * * /bin/sh /usr/local/bin/mosdns-data_update.sh
# !!! Warning: Ensure that you understand every command's behaviour and be careful when identifying large files
# ! Necessary services or software: 'sh' 'systemd or openrc' 'dig' 'tar' 'curl'
# This script will create a log file in /var/log/mosdns/mosdns-data_update.log
#

# Function switch: Rotate logs
rotatelogs="false"

# Script-level Variables
server_name="mosdns"
log_dir="/var/log/$server_name"
log_file="$log_dir/$(basename "$0").log"
mosdns_dir="/etc/mosdns"
backup_dir="/var/backup/mosdns"
max_backups=3
max_log_size=$((1 * 1024 * 1024)) # 1MB

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$log_file")"

# Function: Generate session ID for logging
generate_session_id() {
    # shellcheck disable=SC3028
    echo "$(date +%Y%m%d%H%M%S)$RANDOM"
    # echo "$(date +%Y%m%d%H%M%S)$(awk 'BEGIN{srand();print int(rand()*32768)}')"
}

# Function: Log messages in JSON format
log() {
    _log_level="$1"
    _message="$2"
    _command="$3"
    _line_number="$4"
    _session_id=$(generate_session_id)

    printf '{"timestamp":"%s","log_level":"%s","message":"%s","host_name":"%s","user_name":"%s",' \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" "$_log_level" "$_message" "$(hostname)" "$(whoami)" >>"$log_file"
    printf '"logger_name":"%s","command":"%s","line":"%s","session_id":"%s"}\n' \
        "$(basename "$0")" "$_command" "$_line_number" "$_session_id" >>"$log_file"
}

# Function: Rotate log files when they exceed size limit
rotate_logs() {
    [ ! -f "$log_file" ] && return

    _current_size=$(wc -c <"$log_file")

    [ "$_current_size" -lt "$max_log_size" ] && return

    _log "INFO" "Rotating logs" "rotate_logs" "$LINENO"

    if tar -czf "${log_file}_$(date +%Y%m%d-%H%M%S).tar.gz" "$log_file" >/dev/null 2>&1; then
        : >"$log_file"
        _log "INFO" "Log rotation completed" "rotate_logs" "$LINENO"
    else
        _log "ERROR" "Log rotation failed" "rotate_logs" "$LINENO"
        return 1
    fi

    # Keep only the latest 5 rotated logs
    find "$log_dir" -maxdepth 1 -name "$(basename "$log_file")*tar.gz" -type f -exec ls -1t {} + |
        tail -n +6 | xargs rm -f -- 2>/dev/null
}

# Function: Check required commands
check_commands() {
    log "INFO" "Checking required commands" "check_commands" "$LINENO"
    for cmd in curl tar dig; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "ERROR" "Required command $cmd not found" "check_commands" "$LINENO"
            exit 1
        fi
    done
    log "INFO" "All required commands are available" "check_commands" "$LINENO"
}

# Function: Detect service manager
detect_service_manager() {
    log "INFO" "Detecting service manager" "detect_service_manager" "$LINENO"
    if command -v systemctl >/dev/null 2>&1; then
        _service_cmd="systemctl"
        status_cmd="$_service_cmd status mosdns"
        restart_cmd="$_service_cmd restart mosdns"
        log "INFO" "Using systemd service manager" "detect_service_manager" "$LINENO"
    elif command -v rc-service >/dev/null 2>&1; then
        _service_cmd="rc-service"
        status_cmd="$_service_cmd mosdns status"
        restart_cmd="$_service_cmd mosdns restart"
        log "INFO" "Using OpenRC service manager" "detect_service_manager" "$LINENO"
    else
        log "ERROR" "No compatible service manager found" "detect_service_manager" "$LINENO"
        exit 1
    fi
}

# Function: Check service status
check_service_status() {
    log "INFO" "Starting service status check" "check" "$LINENO"

    mosdns_port=$(grep -m 1 "listen:.*:[0-9]\+" "$mosdns_dir/config.yaml" | awk -F':' '{print $NF}')
    # Default port if not modified in calee/mosdns:/etc/mosdns/config.yaml
    : "${mosdns_port:=5353}" 

    if ! $status_cmd >/dev/null 2>&1; then
        log "ERROR" "Service check failed" "$status_cmd" "$LINENO"
        exit 1
    fi

    if ! dig @127.0.0.1 -p "$mosdns_port" baidu.com +short >/dev/null 2>&1; then
        log "WARNING" "DNS check for baidu.com failed" "dig" "$LINENO"
    fi

    if ! dig @127.0.0.1 -p "$mosdns_port" example.org +short >/dev/null 2>&1; then
        log "WARNING" "DNS check for example.org failed" "dig" "$LINENO"
    fi

    log "INFO" "Service check passed" "check" "$LINENO"
}

# Function: Backup configuration
backup_data() {
    log "INFO" "Starting backup process" "backup" "$LINENO"
    _rule_files="config.yaml rule/blocklist.txt rule/cloudflare-cidr.txt rule/ddnslist.txt rule/disable-ads.txt \
                rule/geoip-only-cn-private_cn.txt rule/geosite_apple.txt rule/geosite_category-ads-all.txt \
                rule/geosite_cn.txt rule/geosite_geolocation-!cn.txt rule/greylist.txt rule/hosts.txt \
                rule/local-ptr.txt rule/redirect.txt rule/whitelist.txt"
    _date=$(date '+%Y%m%d')
    backup_file="mosdns_${_date}.tar.gz"
    temp_backup_dir=$(mktemp -d)

    mkdir -p "${mosdns_dir}"
    mkdir -p "${backup_dir}"

    for _file in $_rule_files; do
        _dir_to_create=$(dirname "${temp_backup_dir}/mosdns/${_file}")
        mkdir -p "${_dir_to_create}"
        if [ -f "${mosdns_dir}/${_file}" ]; then
            cp "${mosdns_dir}/${_file}" "${_dir_to_create}/"
        fi
    done

    if tar czf "${backup_dir}/${backup_file}" -C "${temp_backup_dir}/mosdns" .; then
        log "INFO" "Backup successful" "backup" "$LINENO"
    else
        log "ERROR" "Backup failed" "backup" "$LINENO"
        rm -rf "${temp_backup_dir}"
        return 1
    fi

    rm -rf "${temp_backup_dir}"

    # Keep only the latest backups
    find "$backup_dir" -maxdepth 1 -name "mosdns_*.tar.gz" -type f -exec ls -1t {} + |
        tail -n +$((max_backups + 1)) | xargs rm -f -- 2>/dev/null
    log "INFO" "Old backups cleaned up" "backup" "$LINENO"
}

# Function: Update mosdns
update_data() {
    log "INFO" "Starting update process" "update" "$LINENO"
    tmp_dir=$(mktemp -d)

    cd "${tmp_dir}" || {
        log "ERROR" "Failed to change directory" "update_data" "$LINENO"
        exit 1
    }

    log "INFO" "Fetching latest release information" "update" "$LINENO"
    _url=$(curl -s https://api.github.com/repos/caleee/mosdns/releases/latest | grep -o "https://github.com/caleee/mosdns/releases/download/v.*.tar.gz" | head -n 1)
    if [ -z "$_url" ]; then
        log "ERROR" "No download URL found" "update" "$LINENO"
        exit 1
    else
        log "INFO" "Downloading latest release" "update" "$LINENO"
        if ! curl --connect-timeout 5 -m 60 --ipv4 -kfsSLO "$_url"; then
            if [ $? -eq 28 ]; then
                log "WARNING" "Timeout occurred, retrying with proxy" "update" "$LINENO"
                if ! curl --connect-timeout 5 -m 60 --ipv4 -kfsSLO "https://gh-proxy.com/$_url"; then
                    log "ERROR" "Download failed" "update" "$LINENO"
                    exit 1
                fi
            else
                log "ERROR" "Download failed" "update" "$LINENO"
                exit 1
            fi
        fi

        _file=$(basename "$_url")
        log "INFO" "Unpacking update" "update" "$LINENO"
        if ! tar xzf "$_file" -C /; then
            log "ERROR" "Unpacking failed" "update" "$LINENO"
            exit 1
        fi
    fi

    log "INFO" "Update successful" "update" "$LINENO"
}

# Function: Restart service
restart_service() {
    log "INFO" "Starting service restart" "restart" "$LINENO"
    if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
        log "INFO" "Running inside a container" "restart" "$LINENO"
        log "INFO" "Container will be restarted" "restart" "$LINENO"
        reboot
    else
        log "INFO" "Running on a normal environment" "restart" "$LINENO"
        detect_service_manager
        for _attempt in 1 2; do
            if $restart_cmd; then
                log "INFO" "Service restarted successfully on attempt $_attempt" "restart" "$LINENO"
                return 0
            else
                log "ERROR" "Failed to restart service on attempt $_attempt" "restart" "$LINENO"
                [ "$_attempt" -eq 1 ] && sleep 5
            fi
        done
        return 1
    fi
}

# Function: Restore from backup
restore_data() {
    log "INFO" "Starting restore process" "restore" "$LINENO"
    backup_file=$(find "${backup_dir}" -maxdepth 1 -name "mosdns_*.tar.gz" -type f -exec ls -1t {} + | head -1)

    if [ -z "$backup_file" ]; then
        log "ERROR" "No backup file found" "restore" "$LINENO"
        return 1
    fi

    log "INFO" "Restoring from backup file: $backup_file" "restore" "$LINENO"
    if ! tar xzf "$backup_file" -C "${mosdns_dir}"; then
        log "ERROR" "Restore failed" "restore" "$LINENO"
        return 1
    fi

    log "INFO" "Restore successful" "restore" "$LINENO"
}

# Function: Cleanup on exit
cleanup() {
    cd /tmp || log "WARNING" "Failed to change directory to /tmp" "cleanup" "$LINENO"
    [ -n "${tmp_dir-}" ] && rm -rf "${tmp_dir}"
    [ -n "${temp_backup_dir-}" ] && rm -rf "${temp_backup_dir}"
    log "INFO" "Cleanup completed" "cleanup" "$LINENO"
}

# Main execution
main() {
    check_commands
    [ "$rotatelogs" = "true" ] && rotate_logs
    detect_service_manager
    check_service_status
    backup_data
    update_data
    if ! restart_service; then
        log "WARNING" "Failed to restart service" "main" "$LINENO"
        restore_data
    fi
    restart_service
}

# Trap cleanup
trap cleanup EXIT INT TERM

# Command line interface
if [ $# -eq 0 ]; then
    main
else
    case "$1" in
    check)
        check_service_status
        ;;
    backup)
        backup_data
        ;;
    update)
        update_data
        ;;
    restore)
        restore_data
        ;;
    restart)
        restart_service
        ;;
    *)
        echo "Usage: $0 {check|backup|update|restore|restart}"
        exit 1
        ;;
    esac
fi
