#!/bin/sh
#
# Filename: mosdns.sh
# Author: Cao Lei <caolei@mail.com>
# Date: 2025/02/16
# Version: 1.0.0
# License: Apache 2.0
# Description: This script is used to install mosdns automatically on Linux distributions
#              This script is also used to update mosdns or data
# Usage: Run this script as root: chmod +x mosdns.sh && ./mosdns.sh
# For crontab(root): 0 3 * * * /bin/sh /usr/local/bin/mosdns.sh update-rules
# !!! Warning: Ensure that you understand every command's behaviour and be careful when identifying large files
# ! OS compatibility: 'Ubuntu', 'Debian', 'RedHat', 'CentOS', 'Fedora', 'Alpine'
# ! Necessary services or software: 'sh' 'systemd or openrc' 'dig' 'tar' 'curl'
# This script will create a log file in /var/log/mosdns/mosdns.sh.log
#

# Function switch: Rotate logs
rotatelogs="true"
install_config="true"

# Script-level Variables
server_name="mosdns"
log_dir="/var/log/$server_name"
log_file="$log_dir/$(basename "$0").log"
mosdns_dir="/etc/mosdns"
package_dir=$(mktemp -d)
backup_dir="/tmp/mosdns/backup"
max_backups=3
max_log_size=$((1 * 1024 * 1024)) # 1MB

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$log_file")"

# Function: Generate session ID for logging
generate_session_id() {
    # shellcheck disable=SC3028
    # echo "$(date +%Y%m%d%H%M%S)$RANDOM"
    echo "$(date +%Y%m%d%H%M%S)$(awk 'BEGIN{srand();print int(rand()*32768)}')"
}

# Function: Log messages in JSON format
log() {
    _log_level="$1"
    _message="$2"
    _command="$3"
    _line_number="$4"
    _session_id=$(generate_session_id)

    printf '{"timestamp":"%s","log_level":"%s","message":"%s","host_name":"%s","user_name":"%s",' \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" "$_log_level" "$_message" "$(hostname)" "$USER" >>"$log_file"
    printf '"logger_name":"%s","command":"%s","line":"%s","session_id":"%s"}\n' \
        "$(basename "$0")" "$_command" "$_line_number" "$_session_id" >>"$log_file"
}

# Function: Rotate log files when they exceed size limit
rotate_logs() {
    [ ! -f "$log_file" ] && return

    _current_size=$(wc -c <"$log_file")

    [ "$_current_size" -lt "$max_log_size" ] && return

    log "INFO" "Rotating logs" "rotate_logs" "$LINENO"

    if tar czf "${log_file}_$(date +%Y%m%d-%H%M%S).tar.gz" "$log_file" >/dev/null 2>&1; then
        : >"$log_file"
        log "INFO" "Log rotation completed" "rotate_logs" "$LINENO"
    else
        log "ERROR" "Log rotation failed" "rotate_logs" "$LINENO"
        return 1
    fi

    # Keep only the latest 5 rotated logs
    find "$log_dir" -maxdepth 1 -name "$(basename "$log_file")*tar.gz" -type f -exec ls -1t {} + |
        tail -n +6 | xargs rm -f -- 2>/dev/null
}

# Function: Check if script is running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "This script must be run as root" "id" "$LINENO"
        exit 1
    fi
}

# Function: Detect operating system and version
detect_os() {
    # shellcheck disable=SC1091
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VERSION=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VERSION=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VERSION=$DISTRIB_RELEASE
    else
        OS=$(uname -s)
        VERSION=$(uname -r)
    fi

    if [ -z "$OS" ]; then
        log "ERROR" "Failed to detect OS" "detect_os" "$LINENO"
        exit 1
    fi

    log "INFO" "Detected OS: $OS $VERSION" "detect_os" "$LINENO"
}

# Function: Detect system architecture
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64)
        ARCH="arm64"
        ;;
    *)
        log "ERROR" "Unsupported architecture: $ARCH" "detect_arch" "$LINENO"
        exit 1
        ;;
    esac

    log "INFO" "Detected architecture: $ARCH" "detect_arch" "$LINENO"
}

# Function: Install required dependencies
install_dependencies() {
    log "INFO" "Installing dependencies for $OS" "install_dependencies" "$LINENO"
    _dependencies="curl unzip tar"

    # shellcheck disable=SC2086
    case $OS in
    *Ubuntu* | *Debian*)
        _dig_package="dnsutils"
        if ! apt-get -qq update; then
            log "WARNING" "Failed to update package list" "apt-get" "$LINENO"
        fi
        if ! DEBIAN_FRONTEND=noninteractive apt-get -qq -o=Dpkg::Use-Pty=0 install -y $_dependencies $_dig_package >/dev/null 2>&1; then
            log "ERROR" "Failed to install dependencies" "apt-get" "$LINENO"
            exit 1
        fi
        ;;
    *Red*Hat* | *CentOS* | *Fedora*)
        _dig_package="bind-utils"
        if ! yum -q install -y $_dependencies $_dig_package; then
            log "ERROR" "Failed to install dependencies" "yum" "$LINENO"
            exit 1
        fi
        ;;
    *Alpine*)
        _dig_package="bind-tools"
        if ! apk add --no-cache --quiet $_dependencies $_dig_package; then
            log "ERROR" "Failed to install dependencies" "apk" "$LINENO"
            exit 1
        fi
        ;;
    *)
        log "ERROR" "Unsupported OS: $OS" "install_dependencies" "$LINENO"
        exit 1
        ;;
    esac

    log "INFO" "Dependencies installed successfully" "install_dependencies" "$LINENO"
}

# Function: Download mosdns binary
download_mosdns() {
    log "INFO" "Downloading mosdns" "download_mosdns" "$LINENO"

    _url=$(curl -s https://api.github.com/repos/IrineSistiana/mosdns/releases/latest |
        grep -o "https[^\"]*mosdns-linux-${ARCH}\.zip" | head -n 1)

    if [ -z "$_url" ]; then
        log "ERROR" "Failed to get download URL" "download_mosdns" "$LINENO"
        exit 1
    fi

    if ! curl --connect-timeout 5 -m 120 --ipv4 -kfsSLO "$_url"; then
        if [ $? -eq 28 ]; then
            log "WARNING" "Timeout occurred, retrying with proxy" "curl" "$LINENO"
            if ! curl --connect-timeout 5 -m 120 --ipv4 -kfsSLO "https://gh-proxy.com/$_url"; then
                log "ERROR" "Download failed" "curl" "$LINENO"
                exit 1
            fi
        else
            log "ERROR" "Download failed" "curl" "$LINENO"
            exit 1
        fi
    fi

    _file=$(basename "$_url")
    if ! unzip -q -o "$_file"; then
        log "ERROR" "Failed to unzip $_file" "unzip" "$LINENO"
        exit 1
    fi

    log "INFO" "Downloaded and extracted mosdns successfully" "download_mosdns" "$LINENO"
}

# Function: Download configuration file
download_config() {
    log "INFO" "Downloading mosdns config" "download_config" "$LINENO"

    if ! curl --connect-timeout 5 -m 20 --ipv4 -kfsSLO \
        "https://testingcf.jsdelivr.net/gh/caleee/mosdns@main/etc/mosdns/config.yaml"; then
        if [ $? -eq 28 ]; then
            log "WARNING" "Timeout occurred, retrying with proxy" "curl" "$LINENO"
            if ! curl --connect-timeout 5 -m 20 --ipv4 -kfsSLO \
                "https://cdn.jsdelivr.net/gh/caleee/mosdns@main/etc/mosdns/config.yaml"; then
                log "ERROR" "Download config failed" "curl" "$LINENO"
                exit 1
            fi
        else
            log "ERROR" "Download config failed" "curl" "$LINENO"
            exit 1
        fi
    fi

    log "INFO" "Downloaded mosdns config successfully" "download_config" "$LINENO"
}

# Function: Download rule files
download_rules() {
    log "INFO" "Downloading mosdns rules" "download_rules" "$LINENO"

    _url=$(curl -s https://api.github.com/repos/caleee/mosdns/releases/latest |
        grep -o 'https[^\"]*mosdns-rule\.tar\.gz' | head -n 1)

    if [ -z "$_url" ]; then
        log "ERROR" "Failed to get rule download URL" "download_rules" "$LINENO"
        exit 1
    fi

    if ! curl --connect-timeout 5 -m 60 --ipv4 -kfsSLO "$_url"; then
        if [ $? -eq 28 ]; then
            log "WARNING" "Timeout occurred, retrying with proxy" "curl" "$LINENO"
            if ! curl --connect-timeout 5 -m 60 --ipv4 -kfsSLO "https://gh-proxy.com/$_url"; then
                log "ERROR" "Download rules failed" "curl" "$LINENO"
                exit 1
            fi
        else
            log "ERROR" "Download rules failed" "curl" "$LINENO"
            exit 1
        fi
    fi

    log "INFO" "Downloaded rules successfully" "download_rules" "$LINENO"
}

# Function: Install configuration and rule files
install_data() {
    log "INFO" "Installing mosdns configuration" "install_data" "$LINENO"

    # Create directories
    if ! mkdir -p "$mosdns_dir"; then
        log "ERROR" "Failed to create mosdns directory" "mkdir" "$LINENO"
        exit 1
    fi

    # Install config file
    if [ "$install_config" = "true" ]; then
        if ! install -m 644 "$package_dir/config.yaml" "$mosdns_dir/"; then
            log "ERROR" "Failed to install config file" "install" "$LINENO"
            exit 1
        fi
    fi

    # Install rule files
    if ! tar xzf "$package_dir/mosdns-rule.tar.gz" -C /; then
        log "ERROR" "Failed to extract rule files" "tar" "$LINENO"
        exit 1
    fi

    log "INFO" "Mosdns configuration installed successfully" "install_data" "$LINENO"
}

# Function: Install mosdns binary
install_mosdns() {
    log "INFO" "Installing mosdns binary" "install_mosdns" "$LINENO"

    if ! install -m 755 "$package_dir/mosdns" /usr/local/bin/; then
        log "ERROR" "Failed to install mosdns binary" "install" "$LINENO"
        exit 1
    fi

    # Install service
    if ! mosdns service install -d "$mosdns_dir" -c "$mosdns_dir/config.yaml" >/dev/null 2>&1; then
        log "WARNING" "Failed to install mosdns service" "mosdns" "$LINENO"
    fi

    if command -v mosdns >/dev/null 2>&1; then
        log "INFO" "Mosdns binary installed successfully" "command" "$LINENO"
    else
        log "ERROR" "Failed to install mosdns binary" "command" "$LINENO"
        exit 1
    fi
}

# Function: Handle service management operations
service_manager() {
    _action="$1"

    if command -v systemctl >/dev/null 2>&1; then
        case $_action in
        start)
            systemctl start mosdns
            ;;
        stop)
            systemctl stop mosdns
            ;;
        restart)
            systemctl restart mosdns
            ;;
        status)
            systemctl is-active mosdns --quiet
            ;;
        disable)
            systemctl disable mosdns
            systemctl stop mosdns
            rm -f /etc/systemd/system/mosdns.service
            systemctl daemon-reload
            ;;
        esac
    elif command -v rc-service >/dev/null 2>&1; then
        case $_action in
        start)
            rc-service mosdns start --quiet
            ;;
        stop)
            rc-service mosdns stop
            ;;
        restart)
            rc-service mosdns restart --quiet
            ;;
        status)
            rc-service mosdns status --quiet
            ;;
        disable)
            rc-update del mosdns --quiet
            rc-service mosdns stop --quiet
            rm -f /etc/init.d/mosdns
            ;;
        esac
    elif command -v service >/dev/null 2>&1; then
        case $_action in
        start)
            service mosdns start --quiet
            ;;
        stop)
            service mosdns stop
            ;;
        restart)
            service mosdns restart --quiet
            ;;
        status)
            service mosdns status --quiet
            ;;
        disable)
            service mosdns stop --quiet
            rm -f /etc/init.d/mosdns
            ;;
        esac
    else
        log "ERROR" "No supported service manager found" "service_manager" "$LINENO"
        return 1
    fi
}

# Function: Start mosdns service
service_start() {
    log "INFO" "Starting mosdns service" "service_start" "$LINENO"

    if ! service_manager status; then
        if ! service_manager start; then
            log "ERROR" "Failed to start mosdns service" "service_start" "$LINENO"
            return 1
        fi
        sleep 5
        if ! service_manager status; then
            log "ERROR" "Mosdns service is not running" "service_start" "$LINENO"
            return 1
        fi
    fi

    log "INFO" "Mosdns service is running" "service_start" "$LINENO"
}

# Function: Check service operation status
service_status() {
    log "INFO" "Checking mosdns service status" "service_status" "$LINENO"

    if ! service_manager status; then
        log "ERROR" "Service is not running" "service_status" "$LINENO"
        return 1
    fi

    mosdns_port=$(grep -m 1 "listen:.*:[0-9]\+" "$mosdns_dir/config.yaml" | awk -F':' '{print $NF}')
    # Default port if not modified in calee/mosdns:/etc/mosdns/config.yaml
    : "${mosdns_port:=5353}"

    for domain in "baidu.com" "example.org"; do
        if ! dig @127.0.0.1 -p "$mosdns_port" "$domain" +short >/dev/null 2>&1; then
            log "WARNING" "Mosdns service is not working properly ($domain resolution failed)" "dig" "$LINENO"
            return 1
        else
            log "INFO" "Domain: $domain resolution succeeded" "dig" "$LINENO"
        fi
    done

    log "INFO" "Mosdns service is working properly" "service_status" "$LINENO"
}

# Function: Restart mosdns service
service_restart() {
    log "INFO" "Restarting mosdns service" "service_restart" "$LINENO"

    if ! service_manager restart; then
        log "ERROR" "Failed to restart mosdns service" "service_restart" "$LINENO"
        return 1
    fi

    sleep 5
    service_status
}

# Function: Uninstall mosdns
uninstall_mosdns() {
    echo "Starting mosdns uninstallation"

    check_root

    # Stop and disable service
    service_manager disable
    echo "Mosdns service disabled"

    # Remove binary
    rm -f /usr/local/bin/mosdns
    echo "Mosdns binary removed"

    # Remove configuration and rules
    rm -rf "$mosdns_dir"
    echo "Mosdns configuration and rules removed"

    # Remove logs
    rm -rf "$log_dir"
    echo "Mosdns logs removed"

    # Remove backup directory
    [ -d "/tmp/mosdns" ] && rm -rf "/tmp/mosdns"
    echo "Mosdns backup directory removed"

    echo "Mosdns uninstalled successfully"
}

# Function: Update mosdns binary
update_mosdns() {
    log "INFO" "Starting mosdns update" "update_mosdns" "$LINENO"
    echo "Checking for mosdns updates..."

    # Check if mosdns is installed
    if ! command -v mosdns >/dev/null 2>&1; then
        log "ERROR" "Mosdns is not installed" "command" "$LINENO"
        exit 1
    fi

    # Check service status
    if ! service_manager status; then
        if ! service_manager start; then
            log "ERROR" "Service must be running normally to continue the update" "service_manager" "$LINENO"
            exit 1
        fi
    fi

    # Get current version
    current_version=$(mosdns version | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+')
    if [ -z "$current_version" ]; then
        log "ERROR" "Failed to get current version" "update_mosdns" "$LINENO"
        exit 1
    fi

    # Get latest version
    latest_info=$(curl -s https://api.github.com/repos/IrineSistiana/mosdns/releases/latest)
    latest_version=$(echo "$latest_info" | grep -o '"tag_name": "v[^"]*"' | cut -d'"' -f4)
    if [ -z "$latest_version" ]; then
        log "ERROR" "Failed to get latest version" "update_mosdns" "$LINENO"
        exit 1
    fi

    log "INFO" "Current version: $current_version, Latest version: $latest_version" "update_mosdns" "$LINENO"

    # Compare versions
    if [ "$current_version" = "$latest_version" ]; then
        log "INFO" "Mosdns is already the latest version, no update is needed" "update_mosdns" "$LINENO"
        echo "Mosdns is already the latest version, no update is needed. The latest version: $current_version"
        exit 0
    fi

    if ! mkdir -p "$backup_dir"; then
        log "ERROR" "Failed to create backup directory" "mkdir" "$LINENO"
        exit 1
    fi

    _backup_path="${backup_dir}/mosdns.${current_version}"

    cd "$package_dir" || {
        log "ERROR" "Failed to change directory" "cd" "$LINENO"
        exit 1
    }

    # Backup current binary with version tag
    if ! cp /usr/local/bin/mosdns "$_backup_path"; then
        log "ERROR" "Failed to backup current version" "cp" "$LINENO"
        exit 1
    fi
    log "INFO" "Current version backed up to $_backup_path" "update_mosdns" "$LINENO"

    # Download and install new version
    check_root
    detect_arch
    download_mosdns

    if ! install -m 755 "$package_dir/mosdns" /usr/local/bin/; then
        log "ERROR" "Failed to install new version" "install" "$LINENO"
        exit 1
    fi

    # Restart and verify service
    if ! service_manager restart; then
        log "ERROR" "Failed to restart mosdns service" "service_manager" "$LINENO"
        log "INFO" "Attempting to restore original version" "update_mosdns" "$LINENO"
        if ! install -m 755 "$_backup_path" /usr/local/bin/mosdns; then
            log "ERROR" "Failed to restore original version" "install" "$LINENO"
            log "CRITICAL" "Manual restoration required" "update_mosdns" "$LINENO"
            echo "To restore manually, run: sudo install -m 755 $_backup_path /usr/local/bin/mosdns"
            exit 1
        fi
        if ! service_manager restart; then
            log "ERROR" "Failed to restart service after restoration" "service_manager" "$LINENO"
            log "CRITICAL" "Service is in an inconsistent state" "update_mosdns" "$LINENO"
            echo "Original version is available at: $_backup_path"
            echo "To restore manually, run: sudo install -m 755 $_backup_path /usr/local/bin/mosdns"
            exit 1
        fi
        exit 1
    fi

    log "INFO" "Mosdns updated successfully" "update_mosdns" "$LINENO"
    log "INFO" "Backup version is kept at: $_backup_path" "update_mosdns" "$LINENO"
    echo "Update completed. A backup of the previous version is kept at: $_backup_path"
}

# Function: Update mosdns rules
update_rules() {
    log "INFO" "Starting mosdns rules update" "update_rules" "$LINENO"
    echo "Starting mosdns rules update..."

    # Check if mosdns is installed
    if ! command -v mosdns >/dev/null 2>&1; then
        log "ERROR" "Mosdns is not installed" "command" "$LINENO"
        exit 1
    fi

    # Check service status
    if ! service_manager status; then
        if ! service_manager start; then
            log "ERROR" "Service must be running normally to continue the update" "service_manager" "$LINENO"
            exit 1
        fi
    fi

    # Rotate logs if configured
    [ "$rotatelogs" = "true" ] && rotate_logs

    # Create backup
    _date=$(date '+%Y%m%d%H%M%S')
    _backup_file="mosdns_${_date}.tar.gz"

    if ! mkdir -p "$backup_dir"; then
        log "ERROR" "Failed to create backup directory" "mkdir" "$LINENO"
        exit 1
    fi

    if [ -d "/etc/mosdns" ] && [ -n "$(ls -A /etc/mosdns 2>/dev/null)" ]; then
        if ! tar czf "${backup_dir}/${_backup_file}" -C / etc/mosdns; then
            log "ERROR" "Failed to backup current configuration" "tar" "$LINENO"
            exit 1
        fi
        log "INFO" "Current configuration backed up to ${backup_dir}/${_backup_file}" "update_rules" "$LINENO"
    else
        log "WARNING" "No existing configuration to backup" "update_rules" "$LINENO"
        return 0
    fi

    # Download new configuration
    cd "$package_dir" || {
        log "ERROR" "Failed to change directory" "cd" "$LINENO"
        exit 1
    }

    # Use existing function to download new rules
    download_rules

    # Use existing function to install new rules
    install_config="false"
    if ! install_data; then
        log "ERROR" "Failed to install new rules" "install_data" "$LINENO"
        log "INFO" "Attempting to restore from backup" "update_rules" "$LINENO"
        if ! tar xzf "${backup_dir}/${_backup_file}" -C /; then
            log "ERROR" "Restore failed" "tar" "$LINENO"
            log "CRITICAL" "Manual restoration required" "update_rules" "$LINENO"
            echo "To restore manually, run: sudo tar xzf ${backup_dir}/${_backup_file} -C /"
            exit 1
        fi
        exit 1
    fi

    # Restart and verify service
    if ! service_restart; then
        log "ERROR" "Service failed to restart with new configuration" "service_restart" "$LINENO"
        log "INFO" "Attempting to restore from backup" "update_rules" "$LINENO"
        if ! tar xzf "${backup_dir}/${_backup_file}" -C /; then
            log "ERROR" "Restore failed" "tar" "$LINENO"
            log "CRITICAL" "Manual restoration required" "update_rules" "$LINENO"
            echo "To restore manually, run: sudo tar xzf ${backup_dir}/${_backup_file} -C /"
            exit 1
        fi
        exit 1
    fi

    # Clean old backups (keep last 3)
    find "$backup_dir" -maxdepth 1 -name "mosdns_*.tar.gz" -type f -exec ls -1t {} + |
        tail -n +$((max_backups + 1)) | xargs rm -f -- 2>/dev/null

    log "INFO" "Mosdns rules updated successfully" "update_rules" "$LINENO"
    log "INFO" "Backup is kept at: ${backup_dir}/${_backup_file}" "update_rules" "$LINENO"
    echo "Update completed. A backup of the previous configuration is kept at: ${backup_dir}/${_backup_file}"
}

# Main execution
main() {
    check_root
    detect_os
    detect_arch
    install_dependencies
    cd "$package_dir" || {
        log "ERROR" "Failed to change directory" "cd" "$LINENO"
        exit 1
    }
    download_mosdns
    download_config
    download_rules
    install_data
    install_mosdns
    service_start
    if ! service_status; then
        log "WARNING" "Service check failed after deployment" "service_status" "$LINENO"
        exit 1
    fi
    log "INFO" "Mosdns deployment completed successfully" "main" "$LINENO"
    echo "Mosdns service deployment completed, running normally"
}

# Function: Cleanup on exit
cleanup() {
    cd /tmp || log "WARNING" "Failed to change directory to /tmp" "cleanup" "$LINENO"
    [ -n "${package_dir-}" ] && rm -rf "${package_dir}"
    echo "Please check the log at $log_file"
}

# Trap cleanup
trap cleanup EXIT INT TERM

# Command line interface
if [ $# -eq 0 ]; then
    if command -v mosdns >/dev/null 2>&1; then
        _mosdns_path="/usr/local/bin/mosdns"
        _actual_path=$(which mosdns)
        if [ "$_actual_path" != "$_mosdns_path" ]; then
            log "ERROR" "Detected mosdns at unexpected location: $_actual_path" "main" "$LINENO"
            echo "This script only manages mosdns installed at $_mosdns_path"
            echo "Please uninstall existing mosdns first:"
            echo "1. Stop and remove service using your system's service manager"
            echo "2. Remove binary: sudo rm -f $_actual_path"
            echo "3. Remove data: sudo rm -rf /etc/mosdns"
            exit 1
        fi
        log "INFO" "Mosdns is already installed, starting update process" "main" "$LINENO"
        update_mosdns
    else
        log "INFO" "Mosdns is not installed, starting installation" "main" "$LINENO"
        echo "Installing mosdns..."
        main
    fi
else
    case "$1" in
    install)
        main
        ;;
    update)
        update_mosdns
        ;;
    update-rules)
        update_rules
        ;;
    uninstall)
        uninstall_mosdns
        ;;
    start)
        if service_start; then
            echo "Mosdns service started successfully"
        else
            echo "Mosdns service failed to start"
        fi
        ;;
    stop)
        if service_manager stop; then
            echo "Mosdns service stopped successfully"
        else
            echo "Mosdns service failed to stop"
        fi
        ;;
    restart)
        if service_restart; then
            echo "Mosdns service restarted successfully"
        else
            echo "Mosdns service failed to restart"
        fi
        ;;
    status)
        if service_status; then
            echo "Mosdns service is running normally"
        else
            echo "Mosdns service work is not normal. Please check logs for details"
        fi
        ;;
    *)
        echo "Usage: $0 {install|update|update-rules|uninstall|start|stop|restart|status}"
        exit 1
        ;;
    esac
fi
