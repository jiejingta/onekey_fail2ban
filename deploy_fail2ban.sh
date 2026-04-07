#!/bin/bash
# deploy_fail2ban.sh - 一键部署 fail2ban + SSH 访问频次限制

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; exit 1; }

# ───────────────────────────── 可按需修改的参数 ─────────────────────────────
SSH_PORT=22          # 你的 SSH 端口
MAX_RETRY=5          # 允许失败次数
FIND_TIME=600        # 统计窗口（秒），10 分钟内
BAN_TIME=3600        # 封禁时长（秒），1 小时；-1 表示永久
# ────────────────────────────────────────────────────────────────────────────

[[ $EUID -ne 0 ]] && err "请用 root 执行此脚本"

log "更新包索引..."
apt-get update -qq

log "安装 fail2ban..."
apt-get install -y -qq fail2ban

# ── 主配置（覆盖发行版默认值，升级时不会被覆盖）──
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
# 白名单：本机回环 + 私有网段，按需追加你的跳板机 IP
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

bantime  = ${BAN_TIME}
findtime = ${FIND_TIME}
maxretry = ${MAX_RETRY}

# 使用 systemd 日志后端，兼容无 /var/log/auth.log 的系统
backend = systemd

# 封禁动作：iptables-multiport（支持多端口）
banaction = iptables-multiport

[sshd]
enabled  = true
port     = ${SSH_PORT}
filter   = sshd
logpath  = %(sshd_log)s
maxretry = ${MAX_RETRY}
findtime = ${FIND_TIME}
bantime  = ${BAN_TIME}
EOF

log "配置已写入 /etc/fail2ban/jail.local"

# ── 确保 sshd filter 存在 ──
if [[ ! -f /etc/fail2ban/filter.d/sshd.conf ]]; then
    warn "未找到 sshd filter，尝试从 jail.conf 提取..."
    apt-get install -y -qq fail2ban   # 重装确保完整
fi

# ── 启动 / 重启服务 ──
systemctl enable fail2ban
systemctl restart fail2ban

sleep 2   # 等待服务就绪

log "当前 jail 状态："
fail2ban-client status sshd || warn "sshd jail 状态查询失败，请手动检查"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e " fail2ban 部署完成"
echo -e "  SSH 端口    : ${SSH_PORT}"
echo -e "  失败上限    : ${MAX_RETRY} 次"
echo -e "  统计窗口    : ${FIND_TIME} 秒"
echo -e "  封禁时长    : ${BAN_TIME} 秒  (-1 = 永久)"
echo -e ""
echo -e " 常用命令："
echo -e "  查看被封 IP      : fail2ban-client status sshd"
echo -e "  手动解封         : fail2ban-client set sshd unbanip <IP>"
echo -e "  手动封禁         : fail2ban-client set sshd banip <IP>"
echo -e "  查看实时日志     : journalctl -u fail2ban -f"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
