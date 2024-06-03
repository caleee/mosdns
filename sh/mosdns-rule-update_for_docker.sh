#!/bin/sh
#
# Filename: mosdns-rule-update_for_docker.sh
# Author: Cao Lei <caolei@mail.com>
# Date: 2024/06/03
# Version: 1.0.0
# Description: This script is used to initialize and update mosdns rule data (Limited to docker mirroring: caleee/mosdns:latest)
# Usage: Run this script as root: chmod +x mosdns-rule-update_for_docker.sh && ./mosdns-rule-update_for_docker.sh
# Note: Ensure that you understand every command's behaviour and be careful when identifying large files
#
# For crontab: cp mosdns-rule-update_for_docker.sh /etc/periodic/daily/
#

API_URL="https://api.github.com/repos/caleee/mosdns/releases/latest"
RES_URL="https://github.com/caleee/mosdns/releases/download"
URL=$(curl -s $API_URL | grep -o "$RES_URL/v.*.tar.gz")
SHA_URL=$(curl -s $API_URL | grep -o "$RES_URL/v.*.tar.gz.sha256sum")
FILE=$(basename "$URL")
SHA_FILE=$(basename "$SHA_URL")
LOG_FILE="/var/log/mosdns_date-update.log"
TMP_DIR=$(mktemp -d) && cd "$TMP_DIR" || exit 1
trap 'cd - > /dev/null && rm -rf "$TMP_DIR"' EXIT

log() {
    status="$1"
    cmd="$2"
    message="$3"
    datetime=$(date '+%Y-%m-%dT%H:%M:%S.%6N%:z')
    script_name=$(basename "$0")
    user=$(whoami)
    echo "${datetime} ${status} ${script_name} (${user}) CMD (${cmd}) MSG (${message})" >>"${LOG_FILE}"
}

check_url() {
    log "INFO" "check_url" "Check whether the URL exists."

    if [ -z "$URL" ]; then
        log "ERROR" "curl" "The file download address was not found."
        exit 1
    fi

    if [ -z "$SHA_URL" ]; then
        log "ERROR" "curl" "The SHA256SUM file download address was not found."
        exit 1
    fi
}

download_and_verify() {
    log "INFO" "download_and_verify" "Downloading ${FILE}..."
    if ! curl --connect-timeout 5 -m 60 --ipv4 -kfsSLO "$URL"; then
        log "ERROR" "curl" "Download ${FILE} failed."
        exit 1
    fi
    log "INFO" "download_and_verify" "Download ${FILE} successfully."

    log "INFO" "download_and_verify" "Downloading ${SHA_FILE}..."
    if ! curl --connect-timeout 5 -m 10 --ipv4 -kfsSLO "$SHA_URL"; then
        log "ERROR" "curl" "Download ${SHA_FILE} failed."
        exit 1
    fi
    log "INFO" "download_and_verify" "Download ${SHA_FILE} successfully."

    log "INFO" "download_and_verify" "Verify ${SHA_FILE} checksum..."
    if ! sha256sum --check --quiet "${SHA_FILE}"; then
        log "ERROR" "sha256 --check ${SHA_FILE}" "Verify ${SHA_FILE} failed."
        exit 1
    fi
    log "INFO" "download_and_verify" "Verify ${SHA_FILE} successfully."
}

unpick() {
    log "INFO" "unpick" "Unpacking ${FILE}..."
    if ! tar xzf "$FILE" -C /etc/mosdns; then
        log "ERROR" "tar" "Unpacking ${FILE} failed."
        exit 1
    fi
    log "INFO" "unpick" "Mosdns data unpick successfully."
}

restart() {
    log "INFO" "restart" "Running inside a Docker container"
    log "INFO" "reboot" "The file update is complete, and the container is about to restart."
    cd - >/dev/null && rm -rf "$TMP_DIR"
    reboot
}

update() {
    check_url
    download_and_verify
    unpick
}

if [ $# -eq 0 ]; then
    update
    restart
else
    case "$1" in
    update)
        update
        ;;
    *)
        echo "Usage: $0 update"
        exit 1
        ;;
    esac
fi
