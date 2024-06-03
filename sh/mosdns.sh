#!/bin/bash
#
# Filename: mosdns.sh
# Author: Cao Lei <caolei@mail.com>
# Date: 2024/03/28 - 2024/06/01
# Version: 1.1.0
# Description: This script is used to initialize and update mosdns configuration and data
# Usage: Run this script as root: chmod +x mosdns.sh && ./mosdns.sh
# Note: Ensure that you understand every command's behaviour and be careful when identifying large files
#
# For crontab: 0 3 * * * /etc/mosdns/mosdns.sh >> /var/log/consumer-mosdns-script.log 2>&1
#

LOG_FILE="/var/log/consumer-mosdns-script.log"
MOSDNS_DIR="/etc/mosdns"
BACKUP_DIR="/opt/backup/mosdns"

log() {
    local status cmd message datetime script_name user

    status="$1"
    cmd="$2"
    message="$3"
    datetime=$(date '+%Y-%m-%dT%H:%M:%S.%6N%:z')
    script_name=$(basename "$0")
    user=$(whoami)

    echo "${datetime} ${status} ${script_name} (${user}) CMD (${cmd}) MSG (${message})" >>"${LOG_FILE}"
}

check() {
    if ! systemctl status mosdns >/dev/null 2>&1; then
        log "ERROR" "systemctl status mosdns" "Service check failed"
        exit 1
    fi

    if ! dnslookup baidu.com 127.0.0.1:5353 >/dev/null 2>&1; then
        log "ERROR" "dnslookup baidu.com 127.0.0.1:5353" "DNS check for baidu.com failed"
        exit 1
    fi

    if ! dnslookup example.org 127.0.0.1:5353 >/dev/null 2>&1; then
        log "ERROR" "dnslookup example.org 127.0.0.1:5353" "DNS check for example.org failed"
        exit 1
    fi
}

backup() {
    local mosdns_files date backup_file temp_backup_dir dir_to_create

    mosdns_files=("mosdns.sh" "config_custom.yaml" "config_sample.yaml" "config.yaml" "default.yaml" "rule/blocklist.txt" "rule/cloudflare-cidr.txt" "rule/ddnslist.txt" "rule/disable-ads.txt" "rule/geoip-only-cn-private_cn.txt" "rule/geosite_apple.txt" "rule/geosite_category-ads-all.txt" "rule/geosite_cn.txt" "rule/geosite_geolocation-!cn.txt" "rule/greylist.txt" "rule/hosts.txt" "rule/local-ptr.txt" "rule/redirect.txt" "rule/whitelist.txt")
    date=$(date '+%Y%m%d')
    backup_file="mosdns_${date}.tar.gz"
    temp_backup_dir=$(mktemp -d)

    mkdir -p "${MOSDNS_DIR}"
    mkdir -p "${BACKUP_DIR}"

    for file in "${mosdns_files[@]}"; do
        dir_to_create=$(dirname "${temp_backup_dir}/mosdns/${file}")
        mkdir -p "${dir_to_create}"
        cp "${MOSDNS_DIR}/${file}" "${dir_to_create}/"
    done

    tar czf "${BACKUP_DIR}/${backup_file}" -C "${temp_backup_dir}/mosdns" .
    log "INFO" "tar czf ${BACKUP_DIR}/${backup_file}" "Backup successful"

    rm -rf "${temp_backup_dir}"

    # Keep only the latest 3 backups
    (cd "${BACKUP_DIR}" && ls -t | tail -n +4 | xargs -r rm --)
}

update() {
    local TMP_DIR url file

    TMP_DIR=$(mktemp -d)

    pushd "${TMP_DIR}" >/dev/null || exit 1

    url=$(curl -s https://api.github.com/repos/caleee/mosdns/releases/latest | grep -o "https://github.com/caleee/mosdns/releases/download/v.*.tar.gz")
    if [ -z "$url" ]; then
        log "ERROR" "curl -s https://api.github.com/repos/caleee/mosdns/releases/latest" "No download URL found"
        return 1
    fi

    if ! curl --connect-timeout 5 -m 60 --ipv4 -kfsSLO "$url"; then
        log "ERROR" "curl --connect-timeout 5 -m 60 --ipv4 -kfsSLO $url" "Download failed"
        return 1
    fi

    file=$(basename "$url")

    if ! tar xzf "$file" -C /; then
        log "ERROR" "tar xzf $file -C /" "Unpacking failed"
        return 1
    fi

    popd >/dev/null || exit 1

    rm -rf "${TMP_DIR}"

    log "INFO" "update" "Mosdns update successfully"
}

restart() {
    log "INFO" "systemctl restart" "Start restarting the mosdns service."
    for attempt in 1 2; do
        if systemctl systemctl restart mosdns; then
            log "INFO" "systemctl restart" "Mosdns service successfully restarted on attempt $attempt."
            if systemctl is-active --quiet mosdns.service; then
                log "INFO" "systemctl is-active" "Mosdns service is active and running."
                return 0
            else
                log "INFO" "systemctl is-active" "Mosdns service failed to become active."
            fi
        else
            log "ERROR" "systemctl restart" "Failed to restart mosdns.service on attempt $attempt."
            if [ "$attempt" -eq 1 ]; then
                echo "Waiting 5 seconds before next attempt..."
                sleep 5
            else
                log "CRITICAL" "systemctl restart" "Mosdns service failed to restart after 2 attempts."
                exit 1
            fi
        fi
    done
    log "INFO" "systemctl restart" "Mosdns service restarted successfully."
}

restore() {
    local backup_file

    backup_file=$(ls -t "${BACKUP_DIR}"/mosdns_*.tar.gz | head -1)

    if [ -z "$backup_file" ]; then
        log "ERROR" "ls -t ${BACKUP_DIR}/mosdns_*.tar.gz" "No backup file found to restore"
        return 1
    fi

    if ! tar xzf "$backup_file" -C "${MOSDNS_DIR}"; then
        log "ERROR" "tar xzf $backup_file -C ${MOSDNS_DIR}" "Restore failed"
        return 1
    fi

    log "INFO" "tar xzf $backup_file -C ${MOSDNS_DIR}" "Restore successful"
}

main() {
    check
    backup
    if ! update; then
        restore
    fi
    restart
}

if [ $# -eq 0 ]; then
    main
else
    case "$1" in
    check)
        check
        ;;
    backup)
        backup
        ;;
    update)
        update
        ;;
    restore)
        restore
        ;;
    restart)
        restart
        ;;
    *)
        echo "Usage: $0 {check|backup|update|restore|restart}"
        exit 1
        ;;
    esac
fi
