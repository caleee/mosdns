#!/bin/bash
#
# Filename: get_mosdns-config.sh
# Author: Cao Lei <caolei@mail.com>
# Date: 2024/02/19
# Version: 1.0.0
# Description: A script for extract configuration information and data files from the configured "luci-app-mosdns" application in "openwrt"
# Usage: Run this script: ./get_mosdns-config.sh
# Note: Ensure that you understand every command's behaviour and be careful when identifying large files
#

# Absolute path of the directory where the script is located
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
MOSCONF_DIR="$SCRIPT_DIR/mosdns-config"

# Folders to be backed up
set -- "/etc/mosdns" "/etc/config" "/usr/share/mosdns" "/usr/share/v2ray" "/var/mosdns"

# Check existence of directories
for folder do
  [ -d "${folder}" ] || { echo "${folder} directory doesn't exist"; exit 1; }
done

# Create directories to maintain the same structure
for folder do
  mkdir -p "${MOSCONF_DIR}${folder}"
done

# Copy necessary files while maintaining the original folder structure
STDOUT="Failed to copy"
cp -R /etc/mosdns/* "${MOSCONF_DIR}/etc/mosdns/" || { echo "$STDOUT"; exit 1; }
cp /etc/config/mosdns "${MOSCONF_DIR}/etc/config/" || { echo "$STDOUT"; exit 1; }
cp -R /usr/share/mosdns/* "${MOSCONF_DIR}/usr/share/mosdns/" || { echo "$STDOUT"; exit 1; }
cp -R /usr/share/v2ray/* "${MOSCONF_DIR}/usr/share/v2ray/" || { echo "$STDOUT"; exit 1; }
cp -R /var/mosdns/* "${MOSCONF_DIR}/var/mosdns/" || { echo "$STDOUT"; exit 1; }

# Delete all "*.dump" files recursively in the backup directory
find "${MOSCONF_DIR}" -type f -name '*.dump' -exec rm -f {} \; || { echo "Failed to delete *.dump files"; exit 1; }

# Show the backup directory tree
find "${MOSCONF_DIR}" | sed -e "s/[^-][^\/]*\//   /g" -e "s/   \([^ ]\)/└─ \1/"

# Create the backup archive and save it in "$SCRIPT_DIR"
if ! tar -czf "$SCRIPT_DIR"/mosdns-config.tar.gz . ; then
  echo "Failed to create tar file"
  exit 1
fi

echo "Backup archive created at: $SCRIPT_DIR/mosdns-config.tar.gz"

exit 0

