#!/bin/bash

# Usage: 
# sudo bash setup_disk.sh [K3S_URL] [K3S_TOKEN]

set -e

# --- Configuration ---
SSH_PUB_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANKXFdPbNex1ntXi1AouJU0YOr/B6CzDjvg78DbQ5Qo auto_init"
MOUNT_POINT="/data"
MOUNT_OPTS="rw,relatime"
VG_NAME="vg_data"
LV_NAME="lv_data"
# ---------------------

echo "Step 0: Checking and installing required packages for Ubuntu..."
# Check if running on Ubuntu and install required packages
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" = "ubuntu" ]; then
        echo "Detected Ubuntu system, checking for required packages..."
        
        # Update package list
        apt-get update -y
        
        # Check and install required packages
        if ! command -v pvcreate &> /dev/null || ! command -v vgcreate &> /dev/null || ! command -v lvcreate &> /dev/null; then
            echo "Installing LVM2 package..."
            apt-get install -y lvm2
        fi
    else
        echo "Not running on Ubuntu, skipping package installation."
    fi
else
    echo "Could not determine OS, skipping package installation."
fi

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

# Array to store empty disk paths
empty_disks=()

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
        empty_disks+=("$DEV_PATH")
        echo "Found empty disk: $DEV_PATH"
    else
        echo "Skipping $DEV_PATH: Device is not empty or is the system drive."
    fi
done

if [ ${#empty_disks[@]} -eq 0 ]; then
    echo "No empty disks found. Skipping LVM setup."
else
    echo "Found ${#empty_disks[@]} empty disk(s). Creating LVM with RAID 0..."

    # Check if at least 2 disks are available for RAID 0
    if [ ${#empty_disks[@]} -lt 2 ]; then
        echo "Warning: At least 2 empty disks are required for RAID 0. Using linear (non-RAID) mode with single disk."
        
        # Create physical volume from the single disk
        echo "Creating physical volume..."
        pvcreate "${empty_disks[0]}"
        
        # Create volume group
        echo "Creating volume group: $VG_NAME"
        vgcreate "$VG_NAME" "${empty_disks[0]}"
        
        # Create linear logical volume (not RAID) using all available space
        echo "Creating linear logical volume: $LV_NAME in volume group: $VG_NAME"
        lvcreate -l 100%FREE -n "$LV_NAME" "$VG_NAME"
    else
        # Create physical volumes from each disk
        echo "Creating physical volumes..."
        for disk in "${empty_disks[@]}"; do
            pvcreate "$disk"
        done

        # Create volume group with all disks
        echo "Creating volume group: $VG_NAME"
        vgcreate "$VG_NAME" "${empty_disks[@]}"

        # Create logical volume with RAID 0 using all available space
        echo "Creating logical volume with RAID 0: $LV_NAME in volume group: $VG_NAME"
        lvcreate --type raid0 -l 100%FREE -i${#empty_disks[@]} -I64 "$VG_NAME" -n "$LV_NAME"
    fi

    # Format the logical volume as ext4
    LV_PATH="/dev/$VG_NAME/$LV_NAME"
    echo "Formatting $LV_PATH as ext4..."
    mkfs.ext4 -F "$LV_PATH"

    # Create mount point directory
    mkdir -p "$MOUNT_POINT"

    # Mount the logical volume
    mount -o "$MOUNT_OPTS" "$LV_PATH" "$MOUNT_POINT"

    # Get UUID of the logical volume for fstab
    LV_UUID=$(blkid -s UUID -o value "$LV_PATH")

    # Add entry to /etc/fstab for automatic mounting at boot
    if ! grep -q "$LV_UUID" /etc/fstab; then
        echo "UUID=$LV_UUID $MOUNT_POINT ext4 $MOUNT_OPTS 0 2" >> /etc/fstab
        echo "LVM logical volume successfully added to /etc/fstab."
    fi

    echo "LVM setup complete. Total disks used: ${#empty_disks[@]}"
fi

echo "Step 3: Checking for K3s parameters..."
if [ ! -z "$1" ] && [ ! -z "$2" ]; then
    echo "Invoking K3s join script..."
    # IMPORTANT: Update this URL to your actual GitHub Raw link
    curl -sSL https://raw.githubusercontent.com/unbound-future/infra-bootstrap/main/join_k3s.sh | bash -s -- "$1" "$2"
else
    echo "No K3s parameters provided. Setup complete."
fi