#!/bin/bash
# antiX 安装后配置脚本

echo "开始执行安装后配置..."

# 1. 更新系统
apt-get update
apt-get upgrade -y

# 2. 安装常用工具
apt-get install -y \
    sudo \
    net-tools \
    dnsutils \
    ufw \
    fail2ban \
    logrotate \
    rsync

# 3. 配置 SSH
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

# 4. 配置防火墙
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# 5. 配置时区
timedatectl set-timezone Asia/Shanghai

# 6. 创建普通用户
useradd -m -s /bin/bash admin
echo "admin:Admin@123" | chpasswd
usermod -aG sudo admin

# 7. 配置 sudo 无需密码
echo "admin ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/admin

# 8. 配置自动更新
cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# 9. 配置日志轮转
cat > /etc/logrotate.d/antix-custom << EOF
/var/log/antix/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 640 root adm
    sharedscripts
    postrotate
        systemctl reload rsyslog >/dev/null 2>&1 || true
    endscript
}
EOF

# 10. 创建监控脚本
cat > /usr/local/bin/system-check << 'EOF'
#!/bin/bash
echo "=== 系统状态检查 ==="
echo "时间: $(date)"
echo "运行时间: $(uptime -p)"
echo "负载: $(uptime | awk -F'load average:' '{print $2}')"
echo "内存: $(free -h | awk '/Mem:/ {print $3"/"$2}')"
echo "磁盘: $(df -h / | awk 'NR==2 {print $3"/"$2 " ("$5")"}')"
echo "进程数: $(ps aux | wc -l)"
echo "登录用户: $(who | wc -l)"
EOF

chmod +x /usr/local/bin/system-check

echo "安装后配置完成！"
echo "请立即修改默认密码！"
