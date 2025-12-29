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
cat <<EOF | sudo tee /etc/sysctl.d/90-k3s.conf
# 基础网络转发
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1

# 扩大文件句柄限制 (解决 Pod 启动过多导致的 Too many open files)
fs.file-max = 1000000

# 优化 Inotify 监听 (防止日志收集或 Argo 等组件因文件监听不足报错)
fs.inotify.max_user_instances = 1024
fs.inotify.max_user_watches   = 1048576

# 提高连接跟踪表限制 (在大流量或使用 Service Mesh 时非常重要)
net.netfilter.nf_conntrack_max = 1048576

# 优化 TCP 协议栈
net.ipv4.tcp_slow_start_after_idle = 0
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EOF


swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab
sudo sysctl --system

cat <<EOF | sudo tee /etc/security/limits.d/k3s.conf
* soft nofile 1048576
* hard nofile 1048576
* soft nproc unlimited
* hard nproc unlimited
EOF


apt -y install curl ipvsadm
# Install K3s using the official installer script with specific version and tokens
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" \
  INSTALL_K3S_EXEC="agent --server $K3S_URL --token $K3S_TOKEN" \
  sh -s -

echo "K3s Agent service has been started and joined the cluster."