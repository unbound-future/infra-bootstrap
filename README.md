# Infra-bootsrap Scripts

这是一个用于 Linux 服务器快速初始化、磁盘挂载以及自动加入 K3s 集群的一键式脚本工具包。

## 🚀 功能特性

- **SSH 免密配置**: 自动导入预设的 SSH Ed25519 公钥，确保管理员可以立即远程访问。
- **智能磁盘初始化**:
  - 自动识别系统中未初始化的空白硬盘。
  - 格式化为 `ext4` 文件系统。
  - 挂载至 `/data` 目录。
  - 自动配置 `/etc/fstab`（使用 UUID），支持开机自动挂载，参数为 `rw,relatime`。
- **K3s 快速加入**:
  - 自动下载并安装指定版本 (`v1.33.6+k3s1`) 的 K3s Agent。
  - 通过参数快速接入现有 K3s 集群。
- **在线执行**: 支持通过 `curl` 或 `wget` 远程在线运行，无需预先手动下载脚本。

## 📂 文件说明

- `setup_disk.sh`: 主入口脚本。负责 SSH 导入、磁盘初始化，并根据参数决定是否调用 K3s 加入脚本。
- `join_k3s.sh`: K3s 专用脚本。负责环境检测及 Agent 安装。

## 🛠 快速开始
### 场景 A：仅初始化环境 (SSH + 磁盘)

适用于只需要配置基础环境的服务器：

```bash
curl -sSL https://raw.githubusercontent.com/unbound-future/infra-bootstrap/main/setup_disk.sh | sudo bash
```
需要加入 k3s 集群的服务器
```bash
curl -sSL https://raw.githubusercontent.com/unbound-future/infra-bootstrap/main/join_k3s.sh | sudo bash -s <server_ip> <token>
```