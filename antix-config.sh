#!/bin/bash
# antiX 安装配置

# 系统配置
export ANTIX_VERSION="23.2"
export ANTIX_ARCH="386"  # 可选: 386, amd64
export ANTIX_EDITION="base"  # 可选: base, core, full

# 网络配置
export DEFAULT_SSH_PORT="2222"  # 安装后的 SSH 端口
export DEFAULT_PASSWORD="ChangeMe@123"  # 默认密码

# 分区配置
export DISK_PARTITION_SCHEME="atomic"  # 可选: atomic, lvm, crypto
export SWAP_SIZE="1024"  # 交换分区大小 (MB)
export ROOT_SIZE="8192"  # 根分区最小大小 (MB)

# 软件包配置
export INSTALL_PACKAGES="openssh-server vim curl wget git htop"
export EXCLUDE_PACKAGES=""

# 时区配置
export TIMEZONE="Asia/Shanghai"
export NTP_SERVERS="cn.pool.ntp.org"

# 镜像源配置
export MIRROR_URL="http://ftp.debian.org/debian"
export SECURITY_URL="http://security.debian.org/"

# 安装后脚本
export POST_INSTALL_SCRIPT="post-install.sh"
