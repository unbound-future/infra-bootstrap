#!/bin/bash

# Usage: 
# sudo bash setup_disk.sh [K3S_URL] [K3S_TOKEN]

set -e

# --- Configuration ---
SSH_PUB_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANKXFdPbNex1ntXi1AouJU0YOr/B6CzDjvg78DbQ5Qo auto_init"
MOUNT_BASE="/data"
MOUNT_OPTS="rw,relatime"
# ---------------------

echo "Step 1: Configuring SSH Public Key..."
# Detect the actual home directory even if run via sudo
TARGET_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
[ -z "$TARGET_HOME" ] && TARGET_HOME="$HOME"

mkdir -p "$TARGET_HOME/.ssh"
chmod 700 "$TARGET_HOME/.ssh"

if ! grep -q "$SSH_PUB_KEY" "$TARGET_HOME/.ssh/authorized_keys" 2>/dev/null; then
    echo "$SSH_PUB_KEY" >> "$TARGET_HOME/.ssh/authorized_keys"
    chmod 600 "$TARGET_HOME/.ssh/authorized_keys"
    chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$TARGET_HOME/.ssh"
    echo "SSH public key imported successfully."
else
    echo "SSH public key already exists. Skipping."
fi

echo "Step 2: Detecting and initializing unpartitioned disks..."

disk_count=0

# Loop through all devices of type 'disk'
for dev in $(lsblk -dn -o NAME,TYPE | awk '$2=="disk" {print $1}'); do
    DEV_PATH="/dev/$dev"
    
    # Safety Checks:
    # 1. No child partitions or LVM
    # 2. No existing filesystem
    # 3. Not currently mounted
    child_count=$(lsblk -n "$DEV_PATH" | wc -l)
    fs_type=$(lsblk -dn -o FSTYPE "$DEV_PATH")
    is_mounted=$(lsblk -dn -o MOUNTPOINT "$DEV_PATH")

    if [ "$child_count" -eq 1 ] && [ -z "$fs_type" ] && [ -z "$is_mounted" ]; then
        # Increment counter safely (prevents script exit under set -e)
        
        
        # Determine mount point name: /data, /data2, /data3...
        if [ "$disk_count" -eq 1 ]; then
            TARGET_MOUNT="${MOUNT_BASE}"
        else
            TARGET_MOUNT="${MOUNT_BASE}${disk_count}"
        fi

        echo "Found empty disk: $DEV_PATH. Preparing to mount at $TARGET_MOUNT"

        # Format to ext4
        mkfs.ext4 -F "$DEV_PATH"

        # Create directory and mount
        mkdir -p "$TARGET_MOUNT"
        mount -o "$MOUNT_OPTS" "$DEV_PATH" "$TARGET_MOUNT"

        # Persist in /etc/fstab using UUID
        UUID=$(blkid -s UUID -o value "$DEV_PATH")
        if ! grep -q "$UUID" /etc/fstab; then
            echo "UUID=$UUID $TARGET_MOUNT ext4 $MOUNT_OPTS 0 2" >> /etc/fstab
            echo "Disk $DEV_PATH successfully added to /etc/fstab."
        fi
        disk_count=$((disk_count + 1))
    else
        echo "Skipping $DEV_PATH: Device is not empty or is the system drive."
    fi
done

echo "Total disks initialized: $disk_count"

echo "Step 3: Checking for K3s parameters..."
if [ ! -z "$1" ] && [ ! -z "$2" ]; then
    echo "Invoking K3s join script..."
    # IMPORTANT: Update this URL to your actual GitHub Raw link
    curl -sSL https://raw.githubusercontent.com/unbound-future/infra-bootstrap/main/join_k3s.sh | bash -s -- "$1" "$2"
else
    echo "No K3s parameters provided. Setup complete."
fi
