#!/bin/bash
#
# Filename: install_mosdns.sh
# Author: Cao Lei <caolei@mail.com>
# Date: 2025/02/13
# Version: 1.0.0
# Description: This script is used to install mosdns automatically on Linux distributions
# Usage: Run this script as root: chmod +x install_mosdns.sh && ./install_mosdns.sh
# Note: Ensure that you understand every command's behaviour and be careful when identifying large files
#

LOG_FILE="/var/log/mosdns-install.log"
MOSDNS_DIR="/etc/mosdns"
PACKAGE_DIR="/tmp/mosdns_package"

# Function: Generate session ID for logging
generate_session_id() {
    echo "$(date +%Y%m%d%H%M%S)$RANDOM"
}

# Function: Log messages in JSON format
log() {
    _log_level="$1"
    _message="$2"
    _command="$3"
    _line_number="$4"
    _session_id=$(generate_session_id)

    mkdir -p "$(dirname "$LOG_FILE")"

    printf '{"timestamp":"%s","log_level":"%s","message":"%s","host_name":"%s","user_name":"%s",' \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" "$_log_level" "$_message" "$(hostname)" "$USER" >>"$LOG_FILE"
    printf '"logger_name":"%s","command":"%s","line":"%s","session_id":"%s"}\n' \
        "$(basename "$0")" "$_command" "$_line_number" "$_session_id" >>"$LOG_FILE"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "This script must be run as root" "check_root" "$LINENO"
        return 1
    fi
    return 0
}

detect_os() {
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
        return 1
    fi

    log "INFO" "Detected OS: $OS $VERSION" "detect_os" "$LINENO"
    return 0
}

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
            return 1
            ;;
    esac

    log "INFO" "Detected architecture: $ARCH" "detect_arch" "$LINENO"
    return 0
}

install_dependencies() {
    log "INFO" "Installing dependencies for $OS" "install_dependencies" "$LINENO"
    case $OS in
        *Ubuntu*|*Debian*)
            if ! apt-get update; then
                log "ERROR" "Failed to update package list" "install_dependencies" "$LINENO"
                return 1
            fi
            if ! apt-get install -y curl unzip tar; then
                log "ERROR" "Failed to install dependencies" "install_dependencies" "$LINENO"
                return 1
            fi
            ;;
        *Red*Hat*|*CentOS*|*Fedora*)
            if ! yum install -y curl unzip tar; then
                log "ERROR" "Failed to install dependencies" "install_dependencies" "$LINENO"
                return 1
            fi
            ;;
        *Alpine*)
            if ! apk add --no-cache curl unzip tar openrc; then
                log "ERROR" "Failed to install dependencies" "install_dependencies" "$LINENO"
                return 1
            fi
            ;;
        *)
            log "ERROR" "Unsupported OS: $OS" "install_dependencies" "$LINENO"
            return 1
            ;;
    esac

    log "INFO" "Dependencies installed successfully" "install_dependencies" "$LINENO"
    return 0
}

download_mosdns() {
    _url=""
    _file=""
    mkdir -p "$PACKAGE_DIR" || {
        log "ERROR" "Failed to create package directory" "download_mosdns" "$LINENO"
        return 1
    }
    cd "$PACKAGE_DIR" || {
        log "ERROR" "Failed to change directory" "download_mosdns" "$LINENO"
        return 1
    }

    _url=$(curl -s https://api.github.com/repos/IrineSistiana/mosdns/releases/latest | \
        grep -o "https://github.com/IrineSistiana/mosdns/releases/download/.*/mosdns-linux-${ARCH}.zip" | head -n 1)

    if [ -z "$_url" ]; then
        log "ERROR" "Failed to get download URL" "download_mosdns" "$LINENO"
        return 1
    fi

    _file=$(basename "$_url")
    log "INFO" "Downloading $_file" "download_mosdns" "$LINENO"

    if ! curl --connect-timeout 5 -m 60 --ipv4 -kfsSLO "$_url"; then
        if [ $? -eq 28 ]; then
            log "WARNING" "Timeout occurred, retrying with proxy" "download_mosdns" "$LINENO"
            if ! curl --connect-timeout 5 -m 60 --ipv4 -kfsSLO "https://gh-proxy.com/$_url"; then
                log "ERROR" "Download failed" "download_mosdns" "$LINENO"
                return 1
            fi
        else
            log "ERROR" "Download failed" "download_mosdns" "$LINENO"
            return 1
        fi
    fi

    if ! unzip -o "$_file"; then
        log "ERROR" "Failed to unzip $_file" "download_mosdns" "$LINENO"
        return 1
    fi

    rm -f "$_file"
    log "INFO" "Downloaded and extracted mosdns successfully" "download_mosdns" "$LINENO"
    return 0
}

download_config() {
    _url=""
    _file=""
    cd "$PACKAGE_DIR" || {
        log "ERROR" "Failed to change directory" "download_config" "$LINENO"
        return 1
    }

    _url=$(curl -s https://api.github.com/repos/caleee/mosdns/releases/latest | \
        grep -o "https://github.com/caleee/mosdns/releases/download/.*/mosdns-rule.tar.gz" | head -n 1)

    if [ -z "$_url" ]; then
        log "ERROR" "Failed to get config download URL" "download_config" "$LINENO"
        return 1
    fi

    _file=$(basename "$_url")
    log "INFO" "Downloading $_file" "download_config" "$LINENO"

    if ! curl --connect-timeout 5 -m 60 --ipv4 -kfsSLO "$_url"; then
        if [ $? -eq 28 ]; then
            log "WARNING" "Timeout occurred, retrying with proxy" "download_config" "$LINENO"
            if ! curl --connect-timeout 5 -m 60 --ipv4 -kfsSLO "https://gh-proxy.com/$_url"; then
                log "ERROR" "Download failed" "download_config" "$LINENO"
                return 1
            fi
        else
            log "ERROR" "Download failed" "download_config" "$LINENO"
            return 1
        fi
    fi

    log "INFO" "Downloaded config successfully" "download_config" "$LINENO"
    return 0
}

install_mosdns() {
    log "INFO" "Installing mosdns" "install_mosdns" "$LINENO"
    
    # Install binary
    if ! install -m 755 "$PACKAGE_DIR/mosdns" /usr/bin/; then
        log "ERROR" "Failed to install mosdns binary" "install_mosdns" "$LINENO"
        return 1
    fi
    
    # Create directories
    if ! mkdir -p "$MOSDNS_DIR"; then
        log "ERROR" "Failed to create mosdns directory" "install_mosdns" "$LINENO"
        return 1
    fi
    
    # Install config files
    if ! tar xzf "$PACKAGE_DIR/mosdns-rule.tar.gz" -C /; then
        log "ERROR" "Failed to extract config files" "install_mosdns" "$LINENO"
        return 1
    fi
    
    # Install service
    if ! mosdns service install -d "$MOSDNS_DIR" -c "$MOSDNS_DIR/config.yaml"; then
        log "ERROR" "Failed to install mosdns service" "install_mosdns" "$LINENO"
        return 1
    fi
    
    # Clean up
    rm -rf "$PACKAGE_DIR"
    
    log "INFO" "Mosdns installed successfully" "install_mosdns" "$LINENO"
    return 0
}

check_service() {
    log "INFO" "Checking mosdns service" "check_service" "$LINENO"
    
    if command -v systemctl >/dev/null 2>&1; then
        if ! systemctl is-active --quiet mosdns; then
            if ! systemctl start mosdns; then
                log "ERROR" "Failed to start mosdns service" "check_service" "$LINENO"
                return 1
            fi
        fi
        
        if ! systemctl is-active --quiet mosdns; then
            log "ERROR" "Mosdns service is not running" "check_service" "$LINENO"
            return 1
        fi
    elif command -v rc-service >/dev/null 2>&1; then
        if ! rc-service mosdns status >/dev/null 2>&1; then
            if ! rc-service mosdns start; then
                log "ERROR" "Failed to start mosdns service" "check_service" "$LINENO"
                return 1
            fi
        fi
        
        if ! rc-service mosdns status >/dev/null 2>&1; then
            log "ERROR" "Mosdns service is not running" "check_service" "$LINENO"
            return 1
        fi
    else
        log "ERROR" "No supported service manager found" "check_service" "$LINENO"
        return 1
    fi
    
    log "INFO" "Mosdns service is running" "check_service" "$LINENO"
    return 0
}

main() {
    _exit_code=0

    check_root || {
        _exit_code=$?
        log "ERROR" "Root check failed" "main" "$LINENO"
        exit $_exit_code
    }

    detect_os || {
        _exit_code=$?
        log "ERROR" "OS detection failed" "main" "$LINENO"
        exit $_exit_code
    }

    detect_arch || {
        _exit_code=$?
        log "ERROR" "Architecture detection failed" "main" "$LINENO"
        exit $_exit_code
    }

    install_dependencies || {
        _exit_code=$?
        log "ERROR" "Dependencies installation failed" "main" "$LINENO"
        exit $_exit_code
    }

    download_mosdns || {
        _exit_code=$?
        log "ERROR" "Mosdns download failed" "main" "$LINENO"
        exit $_exit_code
    }

    download_config || {
        _exit_code=$?
        log "ERROR" "Config download failed" "main" "$LINENO"
        exit $_exit_code
    }

    install_mosdns || {
        _exit_code=$?
        log "ERROR" "Mosdns installation failed" "main" "$LINENO"
        exit $_exit_code
    }

    check_service || {
        _exit_code=$?
        log "ERROR" "Service check failed" "main" "$LINENO"
        exit $_exit_code
    }
    
    log "INFO" "Mosdns installation completed successfully" "main" "$LINENO"
    return 0
}

main
exit $?