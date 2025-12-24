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
# Append public key if it doesn't already exist in authorized_keys
if ! grep -q "$SSH_PUB_KEY" ~/.ssh/authorized_keys 2>/dev/null; then
    echo "$SSH_PUB_KEY" >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    echo "SSH public key imported successfully."
else
    echo "SSH public key already exists. Skipping."
fi

echo "Step 2: Detecting and initializing unpartitioned disks..."

# Initialize mount counter
disk_index=1

# Iterate through all block devices of type 'disk'
for dev in $(lsblk -dn -o NAME,TYPE | awk '$2=="disk" {print $1}'); do
    DEV_PATH="/dev/$dev"
    
    # Strict safety checks:
    # 1. Check if the disk has any child devices (partitions, LVM, etc.)
    # 2. Check if the disk has an existing filesystem
    # 3. Check if the disk is already mounted
    child_count=$(lsblk -n "$DEV_PATH" | wc -l)
    fs_type=$(lsblk -dn -o FSTYPE "$DEV_PATH")
    is_mounted=$(lsblk -dn -o MOUNTPOINT "$DEV_PATH")

    if [ "$child_count" -eq 1 ] && [ -z "$fs_type" ] && [ -z "$is_mounted" ]; then
        TARGET_MOUNT="${MOUNT_BASE}${disk_index}"
        echo "Found empty disk: $DEV_PATH. Preparing to mount at $TARGET_MOUNT"

        # Format the disk with ext4
        mkfs.ext4 -F "$DEV_PATH"

        # Create mount directory
        mkdir -p "$TARGET_MOUNT"

        # Perform the mount
        mount -o "$MOUNT_OPTS" "$DEV_PATH" "$TARGET_MOUNT"

        # Persist mount in /etc/fstab using UUID for stability
        UUID=$(blkid -s UUID -o value "$DEV_PATH")
        if ! grep -q "$UUID" /etc/fstab; then
            echo "UUID=$UUID $TARGET_MOUNT ext4 $MOUNT_OPTS 0 2" >> /etc/fstab
            echo "Disk $DEV_PATH (UUID: $UUID) added to /etc/fstab."
        fi

        # Increment index for the next disk
        ((disk_index++))
    else
        echo "Skipping $DEV_PATH: Disk is not empty or is currently in use."
    fi
done

if [ "$disk_index" -eq 1 ]; then
    echo "No eligible empty disks found."
else
    echo "Disk initialization complete. Total disks mounted: $((disk_index-1))."
fi

echo "Step 3: Checking for K3s join parameters..."
if [ ! -z "$1" ] && [ ! -z "$2" ]; then
    echo "Parameters detected. Invoking K3s join script..."
    # Replace the URL below with your actual GitHub Raw URL
    curl -sSL https://raw.githubusercontent.com/<YOUR_USERNAME>/node-init/main/join_k3s.sh | bash -s -- "$1" "$2"
else
    echo "No K3s parameters provided. Initialization finished."
fi