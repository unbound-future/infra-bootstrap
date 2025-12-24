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
mkdir -p ~/.ssh && chmod 700 ~/.ssh
if ! grep -q "$SSH_PUB_KEY" ~/.ssh/authorized_keys 2>/dev/null; then
    echo "$SSH_PUB_KEY" >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    echo "SSH public key imported successfully."
else
    echo "SSH public key already exists. Skipping."
fi

echo "Step 2: Detecting and initializing unpartitioned disks..."

# Initialize disk counter
disk_count=0

# Iterate through all block devices of type 'disk'
# We use a robust check to ensure the disk is truly empty (no partitions/LVM/FS)
for dev in $(lsblk -dn -o NAME,TYPE | awk '$2=="disk" {print $1}'); do
    DEV_PATH="/dev/$dev"
    
    # Safety Checks:
    # 1. child_count == 1 (Only the disk itself, no partitions or LVM children)
    # 2. fs_type is empty
    # 3. is_mounted is empty
    child_count=$(lsblk -n "$DEV_PATH" | wc -l)
    fs_type=$(lsblk -dn -o FSTYPE "$DEV_PATH")
    is_mounted=$(lsblk -dn -o MOUNTPOINT "$DEV_PATH")

    if [ "$child_count" -eq 1 ] && [ -z "$fs_type" ] && [ -z "$is_mounted" ]; then
        ((disk_count++))
        
        # Determine mount point name
        if [ "$disk_count" -eq 1 ]; then
            TARGET_MOUNT="${MOUNT_BASE}"
        else
            TARGET_MOUNT="${MOUNT_BASE}${disk_count}"
        fi

        echo "Found empty disk: $DEV_PATH. Preparing to mount at $TARGET_MOUNT"

        # Format disk to ext4
        mkfs.ext4 -F "$DEV_PATH"

        # Create mount directory and mount
        mkdir -p "$TARGET_MOUNT"
        mount -o "$MOUNT_OPTS" "$DEV_PATH" "$TARGET_MOUNT"

        # Persist mount in /etc/fstab using UUID
        UUID=$(blkid -s UUID -o value "$DEV_PATH")
        if ! grep -q "$UUID" /etc/fstab; then
            echo "UUID=$UUID $TARGET_MOUNT ext4 $MOUNT_OPTS 0 2" >> /etc/fstab
            echo "Disk $DEV_PATH persisted in /etc/fstab."
        fi
    else
        echo "Skipping $DEV_PATH: Disk contains partitions, LVM, or data."
    fi
done

if [ "$disk_count" -eq 0 ]; then
    echo "No eligible empty disks found."
else
    echo "Successfully initialized $disk_count disk(s)."
fi

echo "Step 3: Checking for K3s parameters..."
if [ ! -z "$1" ] && [ ! -z "$2" ]; then
    echo "K3s parameters found. Downloading join script..."
    # Replace the URL below with your actual GitHub Raw URL after uploading
    curl -sSL https://raw.githubusercontent.com/unbound-future/infra-bootstrap/main/join_k3s.sh | bash -s -- "$1" "$2"
else
    echo "No K3s parameters provided. Exiting."
fi