#!/bin/bash

# Arguments: $1=K3S_URL, $2=K3S_TOKEN

K3S_URL=$1
K3S_TOKEN=$2
K3S_VERSION="v1.33.6+k3s1"

# Validate input parameters
if [ -z "$K3S_URL" ] || [ -z "$K3S_TOKEN" ]; then
    echo "Error: K3S_URL and K3S_TOKEN are required."
    exit 1
fi

echo "Starting K3s Agent installation (Version: $K3S_VERSION)..."

# Install K3s using the official installer script with specific version and tokens
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" \
  K3S_URL="$K3S_URL" \
  K3S_TOKEN="$K3S_TOKEN" \
  sh -

echo "K3s Agent service has been started and joined the cluster."