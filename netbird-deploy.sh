#!/usr/bin/env bash

# -----------------------------
# NetBird Silent Deployment
# -----------------------------

set -e


if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root."
    echo "Run: sudo $0"
    exit 1
fi


NETBIRD_VERSION="0.75.0"
MANAGEMENT_URL="https://fs-ztvpn.finsurge.ai"


echo "Downloading NetBird installer..."


curl -fsSL \
    https://pkgs.netbird.io/install.sh \
    -o /tmp/netbird-install.sh


chmod +x /tmp/netbird-install.sh


echo "Installing NetBird ${NETBIRD_VERSION}..."


XDG_CURRENT_DESKTOP=gnome NETBIRD_RELEASE=$NETBIRD_VERSION /tmp/netbird-install.sh


sleep 5


echo "Configuring NetBird management URL..."


netbird up \
    --management-url "$MANAGEMENT_URL"



echo "Checking NetBird service..."


if systemctl is-active --quiet netbird; then
    echo "NetBird service running."
else
    echo "Starting NetBird service..."
    systemctl start netbird
fi


echo "NetBird deployment completed."
