#!/bin/bash
# antix-auto-reinstall.sh - antiX Linux 全自动无人值守安装脚本
# 基于 bin456789/reinstall 项目，实现完全自动化安装
# 使用说明：./antix-auto-reinstall.sh <目标IP> [SSH端口] [root密码]

set -euo pipefail

# ==================== 配置区域 ====================
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 脚本配置
SCRIPT_NAME="antix-auto-reinstall.sh"
REINSTALL_SCRIPT_URL="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
REINSTALL_SCRIPT_PATH="/tmp/reinstall.sh"

# antiX 配置
ANTIX_VERSION="23.2"
ANTIX_ARCH="386"  # 可选: 386, amd64
ANTIX_EDITION="base"  # 可选: base, core, full
ANTIX_ISO_URL="https://sourceforge.net/projects/antix-linux/files/antiX-${ANTIX_VERSION}/antiX-${ANTIX_VERSION}_${ANTIX_ARCH}-${ANTIX_EDITION}.iso"

# 安装配置
DEFAULT_PASSWORD="Antix@123"  # 默认密码，建议修改
DEFAULT_SSH_PORT="22"
INSTALL_LOG_DIR="$HOME/antix-auto-install-logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ==================== 工具函数 ====================
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${PURPLE}[STEP $1]${NC} $2"; }

# 检查依赖
check_dependencies() {
    local missing_deps=()
    
    for cmd in ssh scp sshpass curl wget; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_warning "缺少必要依赖: ${missing_deps[*]}"
        read -p "是否自动安装？(y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y sshpass curl wget
            elif command -v yum &> /dev/null; then
                sudo yum install -y sshpass curl wget
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y sshpass curl wget
            else
                print_error "无法自动安装依赖，请手动安装: ${missing_deps[*]}"
                exit 1
            fi
        else
            print_error "请手动安装依赖后重试: ${missing_deps[*]}"
            exit 1
        fi
    fi
}

# 下载 reinstall.sh
download_reinstall_script() {
    print_step "1" "下载 reinstall.sh 脚本"
    
    if [ -f "$REINSTALL_SCRIPT_PATH" ]; then
        print_info "检测到本地脚本，跳过下载"
        return 0
    fi
    
    print_info "从 GitHub 下载 reinstall.sh..."
    
    # 尝试多个下载源
    local download_success=false
    
    # 源1: GitHub 原始链接
    if curl -s -o "$REINSTALL_SCRIPT_PATH" "$REINSTALL_SCRIPT_URL"; then
        download_success=true
    else
        print_warning "GitHub 源下载失败，尝试国内镜像..."
        # 源2: 国内镜像
        if curl -s -o "$REINSTALL_SCRIPT_PATH" "https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh"; then
            download_success=true
        else
            # 源3: 使用 wget
            if wget -q -O "$REINSTALL_SCRIPT_PATH" "$REINSTALL_SCRIPT_URL"; then
                download_success=true
            fi
        fi
    fi
    
    if [ "$download_success" = true ]; then
        chmod +x "$REINSTALL_SCRIPT_PATH"
        print_success "reinstall.sh 下载完成: $REINSTALL_SCRIPT_PATH"
    else
        print_error "所有下载源都失败，请检查网络连接"
        exit 1
    fi
}

# 生成 antiX preseed 配置文件
generate_preseed_config() {
    local preseed_file="/tmp/antix-preseed.cfg"
    
    cat > "$preseed_file" << 'EOF'
# antiX Linux 无人值守安装配置文件
# 基于 Debian preseed 机制

# 本地化设置
d-i debian-installer/locale string en_US.UTF-8
d-i console-setup/ask_detect boolean false
d-i keyboard-configuration/xkb-keymap select us

# 网络配置
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string antix-auto
d-i netcfg/get_domain string local

# 镜像源设置
d-i mirror/country string manual
d-i mirror/http/hostname string ftp.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

# 用户设置
d-i passwd/root-login boolean true
d-i passwd/root-password password Antix@123
d-i passwd/root-password-again password Antix@123
d-i passwd/make-user boolean false

# 时钟和时区
d-i time/zone string UTC
d-i clock-setup/utc boolean true
d-i clock-setup/ntp boolean true

# 磁盘分区
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-auto/expert_recipe string \
    boot-root :: \
        512 512 512 ext4 \
            $primary{ } $bootable{ } \
            method{ format } format{ } \
            use_filesystem{ } filesystem{ ext4 } \
            mountpoint{ /boot } \
        . \
        1024 1024 1024 swap \
            method{ swap } format{ } \
        . \
        5120 10000 -1 ext4 \
            method{ format } format{ } \
            use_filesystem{ } filesystem{ ext4 } \
            mountpoint{ / } \
        .
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

# 基础系统安装
d-i base-installer/install-recommends boolean false
d-i apt-setup/use_mirror boolean false

# 软件包选择
tasksel tasksel/first multiselect standard
d-i pkgsel/include string openssh-server vim curl wget

# 引导加载程序
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true
d-i grub-installer/bootdev string /dev/sda

# 完成安装
d-i finish-install/reboot_in_progress note
d-i debian-installer/exit/poweroff boolean false
EOF
    
    print_success "Preseed 配置文件已生成: $preseed_file"
    echo "$preseed_file"
}

# 预检目标主机
preflight_check() {
    local host=$1
    local port=$2
    local password=$3
    
    print_step "2" "预检目标主机: $host"
    
    # 检查网络连通性
    print_info "检查网络连通性..."
    if ! ping -c 2 -W 1 "$host" &> /dev/null; then
        print_warning "无法 ping 通主机，但可能禁用了 ICMP，继续尝试 SSH..."
    fi
    
    # 检查 SSH 连接
    print_info "检查 SSH 连接..."
    if ! sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$port" "root@$host" "echo 'SSH连接测试成功'" &> /dev/null; then
        print_error "SSH 连接失败，请检查："
        print_error "1. 目标主机是否开启 SSH 服务"
        print_error "2. 防火墙是否放行端口 $port"
        print_error "3. root 密码是否正确"
        return 1
    fi
    
    # 检查磁盘空间
    print_info "检查磁盘空间..."
    local disk_info
    disk_info=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "root@$host" "df -h / | tail -1" 2>/dev/null || echo "")
    
    if [ -n "$disk_info" ]; then
        local avail_space
        avail_space=$(echo "$disk_info" | awk '{print $4}')
        print_info "根分区可用空间: $avail_space"
        
        # 检查是否足够安装（至少 5GB）
        local num_part=${avail_space:0:-1}
        local unit=${avail_space: -1}
        
        if [ "$unit" = "G" ] && [ "$(echo "$num_part < 5" | bc 2>/dev/null || echo 0)" -eq 1 ]; then
            print_warning "可用空间可能不足（建议至少 5GB）"
        fi
    fi
    
    # 检查内存
    print_info "检查内存..."
    local mem_info
    mem_info=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "root@$host" "free -m | awk '/Mem:/ {print \$2}'" 2>/dev/null || echo "0")
    
    if [ "$mem_info" -lt 512 ]; then
        print_warning "内存较低（${mem_info}MB），antiX 最低要求 256MB，但 512MB 以上体验更佳"
    else
        print_info "内存: ${mem_info}MB"
    fi
    
    print_success "预检通过"
    return 0
}

# 执行自动化安装
execute_auto_install() {
    local host=$1
    local port=$2
    local password=$3
    local log_file="$INSTALL_LOG_DIR/${host}_${TIMESTAMP}.log"
    
    print_step "3" "开始全自动安装到: $host"
    
    # 创建日志目录
    mkdir -p "$INSTALL_LOG_DIR"
    
    {
        echo "=========================================="
        echo "antiX Linux 全自动安装日志"
        echo "目标主机: $host"
        echo "开始时间: $(date)"
        echo "=========================================="
    } > "$log_file"
    
    # 上传 reinstall.sh 到目标主机
    print_info "上传 reinstall.sh 到目标主机..."
    if sshpass -p "$password" scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 -P "$port" \
        "$REINSTALL_SCRIPT_PATH" "root@$host:/tmp/reinstall.sh" 2>> "$log_file"; then
        print_success "脚本上传成功"
    else
        print_error "脚本上传失败"
        return 1
    fi
    
    # 在目标主机上设置执行权限
    sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "root@$host" \
        "chmod +x /tmp/reinstall.sh" 2>> "$log_file"
    
    # 生成 preseed 配置文件并上传
    print_info "配置无人值守安装参数..."
    local preseed_file
    preseed_file=$(generate_preseed_config)
    
    if sshpass -p "$password" scp -o StrictHostKeyChecking=no -P "$port" \
        "$preseed_file" "root@$host:/tmp/preseed.cfg" 2>> "$log_file"; then
        print_success "Preseed 配置文件上传成功"
    else
        print_warning "Preseed 配置文件上传失败，将使用默认配置"
    fi
    
    # 执行自动化安装命令
    print_info "启动全自动安装进程..."
    
    # 构建安装命令
    local install_cmd="/tmp/reinstall.sh alpine --hold 1"
    install_cmd="$install_cmd --password \"$DEFAULT_PASSWORD\""
    install_cmd="$install_cmd --ssh-port $DEFAULT_SSH_PORT"
    
    # 添加 preseed 配置（如果可用）
    if sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "root@$host" \
        "[ -f /tmp/preseed.cfg ] && echo 'Preseed file exists'" &> /dev/null; then
        install_cmd="$install_cmd --preseed /tmp/preseed.cfg"
    fi
    
    # 在 screen 会话中执行安装（防止 SSH 断开）
    print_info "在 screen 会话中启动安装..."
    
    local screen_cmd="screen -dmS antix_auto_install bash -c '$install_cmd | tee /tmp/antix_install.log'"
    
    if sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "root@$host" \
        "$screen_cmd" 2>> "$log_file"; then
        print_success "安装进程已启动（screen 会话: antix_auto_install）"
    else
        print_warning "screen 启动失败，尝试直接后台执行..."
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "root@$host" \
            "nohup $install_cmd > /tmp/antix_install.log 2>&1 &" 2>> "$log_file"
        print_success "安装进程已启动（后台运行）"
    fi
    
    # 获取进程 ID
    local pid
    pid=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "root@$host" \
        "pgrep -f 'reinstall.sh' | head -1" 2>/dev/null || echo "")
    
    if [ -n "$pid" ]; then
        print_info "安装进程 PID: $pid"
        echo "安装进程PID: $pid" >> "$log_file"
    fi
    
    # 保存连接和监控信息
    local info_file="$INSTALL_LOG_DIR/${host}_connection.info"
    cat > "$info_file" << EOF
antiX Linux 全自动安装 - 连接信息
==========================================
目标主机: $host
SSH端口: $port
安装时间: $(date)
安装脚本: /tmp/reinstall.sh
日志文件: /tmp/antix_install.log
Screen会话: antix_auto_install (如果可用)

安装配置:
- 系统版本: antiX ${ANTIX_VERSION} ${ANTIX_ARCH}-${ANTIX_EDITION}
- 默认用户: root
- 默认密码: ${DEFAULT_PASSWORD}
- SSH端口: ${DEFAULT_SSH_PORT}

监控命令:
1. 查看实时日志:
   sshpass -p '${password}' ssh -p ${port} root@${host} 'tail -f /tmp/antix_install.log'
   
2. 进入 screen 会话:
   sshpass -p '${password}' ssh -p ${port} root@${host} 'screen -r antix_auto_install'
   
3. 检查进程状态:
   sshpass -p '${password}' ssh -p ${port} root@${host} 'ps aux | grep reinstall.sh'
   
4. 查看安装进度:
   sshpass -p '${password}' ssh -p ${port} root@${host} 'tail -20 /tmp/antix_install.log'

安装流程:
1. 启动到 Alpine Live 环境
2. 自动下载 antiX ISO
3. 应用 preseed 无人值守配置
4. 自动分区和安装系统
5. 安装完成后自动重启

重要提示:
- 安装会格式化整个硬盘，请确保已备份数据！
- 安装过程约 20-40 分钟，请勿断电！
- 安装完成后可通过 SSH 连接: ssh root@${host} -p ${DEFAULT_SSH_PORT}
EOF
    
    print_success "安装信息已保存: $info_file"
    print_success "本地日志文件: $log_file"
    
    # 显示监控信息
    print_step "4" "安装监控信息"
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${GREEN}🎉 全自动安装已启动！${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo -e "\n${YELLOW}安装进度监控:${NC}"
    echo -e "1. ${GREEN}实时日志:${NC}"
    echo -e "   sshpass -p '${password}' ssh -p ${port} root@${host} 'tail -f /tmp/antix_install.log'"
    echo -e "\n2. ${GREEN}安装状态检查:${NC}"
    echo -e "   sshpass -p '${password}' ssh -p ${port} root@${host} 'tail -10 /tmp/antix_install.log'"
    echo -e "\n3. ${GREEN}详细安装信息:${NC}"
    echo -e "   查看: $info_file"
    echo -e "\n${YELLOW}预计安装时间: 20-40 分钟${NC}"
    echo -e "${YELLOW}安装完成后可通过以下方式连接:${NC}"
    echo -e "   ssh root@${host} -p ${DEFAULT_SSH_PORT}"
    echo -e "   密码: ${DEFAULT_PASSWORD}"
    echo -e "${CYAN}==========================================${NC}"
    
    return 0
}

# 批量部署模式
batch_deploy() {
    local host_file=$1
    
    if [ ! -f "$host_file" ]; then
        print_error "主机列表文件不存在: $host_file"
        exit 1
    fi
    
    print_info "开始批量部署，主机数: $(wc -l < "$host_file")"
    
    local success_count=0
    local fail_count=0
    local total_count=0
    
    # 创建批量日志目录
    local batch_log_dir="$INSTALL_LOG_DIR/batch_${TIMESTAMP}"
    mkdir -p "$batch_log_dir"
    
    while IFS=, read -r host port password notes || [ -n "$host" ]; do
        # 跳过注释和空行
        [[ "$host" =~ ^#.* ]] && continue
        [[ -z "$host" ]] && continue
        
        total_count=$((total_count + 1))
        
        echo -e "\n${CYAN}==========================================${NC}"
        echo -e "${CYAN}处理第 ${total_count} 台主机: ${host}${NC}"
        if [ -n "$notes" ]; then
            echo -e "${CYAN}备注: ${notes}${NC}"
        fi
        echo -e "${CYAN}==========================================${NC}"
        
        # 设置默认值
        port=${port:-$DEFAULT_SSH_PORT}
        password=${password:-$DEFAULT_PASSWORD}
        
        # 执行安装
        if execute_auto_install "$host" "$port" "$password"; then
            success_count=$((success_count + 1))
            echo "$host,$port: 部署成功 - $(date)" >> "$batch_log_dir/batch_result.txt"
        else
            fail_count=$((fail_count + 1))
            echo "$host,$port: 部署失败 - $(date)" >> "$batch_log_dir/batch_result.txt"
        fi
        
        # 延迟一下，避免同时连接太多
        sleep 3
        
    done < "$host_file"
    
    # 生成批量部署报告
    local report_file="$batch_log_dir/deployment_report.md"
    cat > "$report_file" << EOF
# antiX Linux 批量部署报告
## 部署概览
- **部署时间**: $(date)
- **总主机数**: $total_count
- **成功数量**: $success_count
- **失败数量**: $fail_count
- **成功率**: $(echo "scale=2; $success_count * 100 / $total_count" | bc)%

## 详细结果
\`\`\`
$(cat "$batch_log_dir/batch_result.txt" 2>/dev/null || echo "无结果")
\`\`\`

## 后续操作
1. 检查失败主机的日志文件
2. 验证成功主机的 SSH 连接
3. 根据需要修改默认密码
4. 部署应用和服务

## 连接信息
默认 SSH 连接信息:
- 用户名: root
- 密码: $DEFAULT_PASSWORD
- 端口: $DEFAULT_SSH_PORT

**注意**: 首次登录后请立即修改密码！
EOF
    
    echo -e "\n${CYAN}==========================================${NC}"
    echo -e "${GREEN}批量部署完成${NC}"
    echo -e "${GREEN}成功: ${success_count}${NC}"
    echo -e "${RED}失败: ${fail_count}${NC}"
    echo -e "${CYAN}总计: ${total_count}${NC}"
    echo -e "${CYAN}详细报告: $report_file${NC}"
    echo -e "${CYAN}==========================================${NC}"
}

# 显示使用说明
show_usage() {
    echo -e "${CYAN}antiX Linux 全自动无人值守安装脚本${NC}"
    echo -e "${CYAN}基于 bin456789/reinstall 项目${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo
    echo -e "${GREEN}使用方法:${NC}"
    echo "  $0 [选项] <目标IP> [SSH端口] [root密码]"
    echo "  $0 --batch <主机列表文件>"
    echo
    echo -e "${GREEN}选项:${NC}"
    echo "  -h, --help          显示此帮助信息"
    echo "  -b, --batch         批量部署模式"
    echo "  -p, --port          指定 SSH 端口（默认: 22）"
    echo "  -v, --version       指定 antiX 版本（默认: 23.2）"
    echo "  -a, --arch          指定架构（386/amd64，默认: 386）"
    echo "  -e, --edition       指定版本（base/core/full，默认: base）"
    echo "  --password          设置默认密码（默认: Antix@123）"
    echo "  --no-preflight      跳过预检"
    echo
    echo -e "${GREEN}示例:${NC}"
    echo "  1. 单机部署（交互式输入密码）:"
    echo "     $0 192.168.1.100"
    echo
    echo "  2. 单机部署（指定所有参数）:"
    echo "     $0 192.168.1.100 22 mypassword"
    echo
    echo "  3. 批量部署:"
    echo "     $0 --batch hosts.txt"
    echo
    echo -e "${GREEN}主机列表文件格式 (CSV):${NC}"
    echo "  # IP,端口,密码,备注"
    echo "  192.168.1.100,22,password1,测试服务器1"
    echo "  192.168.1.101,2222,password2,测试服务器2"
    echo "  192.168.1.102,,password3  # 使用默认端口22"
    echo
    echo -e "${YELLOW}安装流程:${NC}"
    echo "  1. 下载 reinstall.sh 脚本"
    echo "  2. 预检目标主机"
    echo "  3. 生成无人值守配置文件"
    echo "  4. 上传并执行安装"
    echo "  5. 自动完成所有安装步骤"
    echo "  6. 显示监控信息"
    echo
    echo -e "${RED}⚠️  警告:${NC}"
    echo "  - 安装会格式化整个硬盘，请先备份重要数据！"
    echo "  - 默认密码为 Antix@123，安装后请立即修改！"
    echo "  - 安装过程约 20-40 分钟，请勿断电！"
    echo
    echo -e "${CYAN}更多信息: https://github.com/bin456789/reinstall${NC}"
}

# 主函数
main() {
    # 解析参数
    local batch_mode=false
    local no_preflight=false
    local target_host=""
    local ssh_port="$DEFAULT_SSH_PORT"
    local ssh_password=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -b|--batch)
                batch_mode=true
                shift
                ;;
            --no-preflight)
                no_preflight=true
                shift
                ;;
            -p|--port)
                ssh_port="$2"
                shift 2
                ;;
            -v|--version)
                ANTIX_VERSION="$2"
                shift 2
                ;;
            -a|--arch)
                ANTIX_ARCH="$2"
                shift 2
                ;;
            -e|--edition)
                ANTIX_EDITION="$2"
                shift 2
                ;;
            --password)
                DEFAULT_PASSWORD="$2"
                shift 2
                ;;
            *)
                if [ -z "$target_host" ]; then
                    target_host="$1"
                elif [ -z "$ssh_port" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
                    ssh_port="$1"
                elif [ -z "$ssh_password" ]; then
                    ssh_password="$1"
                fi
                shift
                ;;
        esac
    done
    
    # 显示欢迎信息
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}    antiX Linux 全自动无人值守安装工具${NC}"
    echo -e "${CYAN}    基于 reinstall.sh 自动化框架${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo
    
    # 批量模式
    if [ "$batch_mode" = true ]; then
        if [ -z "$target_host" ]; then
            print_error "批量模式需要指定主机列表文件"
            show_usage
            exit 1
        fi
        check_dependencies
        download_reinstall_script
        batch_deploy "$target_host"
        exit 0
    fi
    
    # 单机模式
    if [ -z "$target_host" ]; then
        print_error "请指定目标主机 IP"
        show_usage
        exit 1
    fi
    
    # 检查依赖
    check_dependencies
    
    # 下载脚本
    download_reinstall_script
    
    # 获取密码（如果未提供）
    if [ -z "$ssh_password" ]; then
        echo -e "${YELLOW}请输入目标主机 root 密码（输入不会显示）:${NC}"
        read -s -r ssh_password
        echo
        if [ -z "$ssh_password" ]; then
            print_error "密码不能为空"
            exit 1
        fi
    fi
    
    # 预检
    if [ "$no_preflight" != true ]; then
        if ! preflight_check "$target_host" "$ssh_port" "$ssh_password"; then
            read -p "预检失败，是否继续？(y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
    
    # 确认安装
    echo -e "${RED}⚠️  ⚠️  ⚠️  重要警告 ⚠️  ⚠️  ⚠️${NC}"
    echo -e "${RED}此操作将格式化目标主机 ${target_host} 的整个硬盘！${NC}"
    echo -e "${RED}所有数据都将丢失，请确保已备份重要数据！${NC}"
    echo
    echo -e "${YELLOW}安装配置:${NC}"
    echo -e "  系统版本: antiX ${ANTIX_VERSION} ${ANTIX_ARCH}-${ANTIX_EDITION}"
    echo -e "  默认用户: root"
    echo -e "  默认密码: ${DEFAULT_PASSWORD}"
    echo -e "  SSH端口: ${DEFAULT_SSH_PORT}"
    echo
    read -p "确认开始全自动安装？(输入 YES 继续): " -r confirm
    if [ "$confirm" != "YES" ]; then
        print_error "安装已取消"
        exit 0
    fi
    
    # 执行安装
    execute_auto_install "$target_host" "$ssh_port" "$ssh_password"
    
    echo -e "\n${CYAN}==========================================${NC}"
    echo -e "${GREEN}🎉 全自动安装任务已成功启动！${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo -e "\n${YELLOW}安装完成后:${NC}"
    echo "1. 系统将自动重启进入 antiX Linux"
    echo "2. 可通过 SSH 连接: ssh root@${target_host} -p ${DEFAULT_SSH_PORT}"
    echo "3. 密码: ${DEFAULT_PASSWORD}"
    echo "4. 首次登录后请立即修改密码！"
    echo -e "\n${CYAN}祝您安装顺利！🚀${NC}"
}

# 异常处理
trap 'print_error "脚本被用户中断"; exit 1' INT TERM
trap 'print_error "脚本执行出错，行号: $LINENO"; exit 1' ERR

# 运行主函数
main "$@"
