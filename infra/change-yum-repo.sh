#!/bin/bash
# =====================================================================
#  change-yum-repo.sh —— Rocky Linux 一键换国内源（阿里云）
#
#  【干什么用】
#    把系统自带的 base / appstream / crb / extras 源，以及 EPEL 扩展源，
#    全部从国外官方地址改成阿里云镜像，解决装包慢、装包超时的问题。
#
#  【怎么用】
#    1) 上传到任意一台机器：  scp change-yum-repo.sh root@192.168.80.10:/root/
#    2) 执行：                bash /root/change-yum-repo.sh
#    3) 看最后两个测试是否都是 [OK]，是就成功了
#
#    想先看看不落地？  bash change-yum-repo.sh --dry-run     （只打印将要改的源地址）
#
#  【适用系统】
#    Rocky Linux 9 / 10 通用（脚本自动读系统版本号，不用手动改数字）
#    实测通过：Rocky Linux 10.2 (Red Quartz)
#
#  【安全性】
#    - 改之前会把 /etc/yum.repos.d/*.repo 完整备份到 /root/yum-repos-backup-时间戳/
#    - 重复执行不会出问题（幂等），改第二次结果和第一次一样
#
#  【出问题怎么回滚】
#    脚本跑完会打印那一行回滚命令，形如：
#    cp -a /root/yum-repos-backup-20260930-125508/*.repo /etc/yum.repos.d/ \
#       && dnf clean all && dnf makecache
#
#  【改完之后源长什么样】
#    baseos    -> https://mirrors.aliyun.com/rockylinux/10/BaseOS/x86_64/os/
#    appstream -> https://mirrors.aliyun.com/rockylinux/10/AppStream/x86_64/os/
#    crb       -> https://mirrors.aliyun.com/rockylinux/10/CRB/x86_64/os/
#    epel      -> https://mirrors.aliyun.com/epel/10/Everything/x86_64/
# =====================================================================

set -uo pipefail

# ---------------------------------------------------------------------
# 可调变量：想换其他镜像站（华为云、中科大），改这两行就行
# ---------------------------------------------------------------------
ROCKY_MIRROR="https://mirrors.aliyun.com/rockylinux"
EPEL_MIRROR="https://mirrors.aliyun.com/epel"

BACKUP_DIR="/root/yum-repos-backup-$(date +%Y%m%d-%H%M%S)"

# 输出用的几个小函数，只为了让结果一眼看清
GRN='\033[32m'; RED='\033[31m'; BLD='\033[1m'; RST='\033[0m'
say()  { printf "\n${BLD}%s${RST}\n" "$*"; }
info() { printf "    %s\n" "$*"; }
ok()   { printf "    ${GRN}[OK]${RST}   %s\n" "$*"; }
bad()  { printf "    ${RED}[FAIL]${RST} %s\n" "$*"; return 0; }

# ---------------------------------------------------------------------
# 0. 环境检查 + 备份
# ---------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || { echo "请用 root 执行：sudo bash $0"; exit 1; }

say "0. 环境检查"
. /etc/os-release                 # 读 /etc/os-release 拿到 VERSION_ID
MAJOR="${VERSION_ID%%.*}"         # 10.2 -> 10，后面拼 epel-release-latest-10 用
info "系统：$PRETTY_NAME"
info "主版本号：$MAJOR"

if [ "${1:-}" = "--dry-run" ]; then
    say "预演模式（--dry-run），不实际修改任何文件"
    info "Rocky 源将指向：$ROCKY_MIRROR/\$releasever/..."
    info "EPEL  源将指向：$EPEL_MIRROR/\$releasever/Everything/\$basearch/"
    info "CRB   源将被启用"
    info "epel-testing / epel-next 将被禁用"
    exit 0
fi

mkdir -p "$BACKUP_DIR"
cp -a /etc/yum.repos.d/*.repo "$BACKUP_DIR"/ 2>/dev/null
ok "原配置已备份到 $BACKUP_DIR"

# ---------------------------------------------------------------------
# 1. Rocky 官方源 -> 阿里云
#
#    系统自带的 repo 文件长这样（mirrorlist 生效、baseurl 被注释掉）：
#      mirrorlist=https://mirrors.rockylinux.org/mirrorlist?...   <- 国外，慢
#      #baseurl=http://dl.rockylinux.org/$contentdir/$releasever/BaseOS/$basearch/os/
#    所以做三件事：
#      a) 把 mirrorlist 注释掉（否则它优先级高于 baseurl，改了也白改）
#      b) 把 #baseurl 的注释去掉，让它生效
#      c) 把 baseurl 里的域名换成阿里云
# ---------------------------------------------------------------------
say "1. 切换 Rocky 官方源 → 阿里云"
for f in /etc/yum.repos.d/rocky*.repo; do
    [ -e "$f" ] || continue
    sed -i \
        -e 's|^mirrorlist=|#mirrorlist=|g' \
        -e 's|^#baseurl=|baseurl=|g' \
        -e "s|http://dl.rockylinux.org/\$contentdir|$ROCKY_MIRROR|g" \
        -e "s|https://dl.rockylinux.org/\$contentdir|$ROCKY_MIRROR|g" \
        -e 's|http://mirrors.aliyun.com|https://mirrors.aliyun.com|g' \
        "$f"
done

if grep -q "$ROCKY_MIRROR" /etc/yum.repos.d/rocky*.repo; then
    ok "base 源已指向阿里云"
    grep -h '^baseurl=' /etc/yum.repos.d/rocky*.repo | sort -u | head -6 | sed 's/^/         /'
else
    bad "base 源替换未生效，请把 /etc/yum.repos.d/rocky.repo 内容发出来排查"
fi

# ---------------------------------------------------------------------
# 2. 启用 CRB 源
#    CRB = CodeReady Builder，很多 EPEL 包的依赖在里面，默认关闭必须开，
#    否则后面装东西会报 "nothing provides xxx"
# ---------------------------------------------------------------------
say "2. 启用 CRB 源（EPEL 依赖）"
if rpm -q dnf-plugins-core >/dev/null 2>&1 || dnf install -y dnf-plugins-core >/dev/null 2>&1; then
    dnf config-manager --set-enabled crb >/dev/null 2>&1   # 有 dnf 插件就用官方命令开
else
    sed -i '/^\[crb\]/,/^\[/ s/^enabled=0/enabled=1/' /etc/yum.repos.d/rocky*.repo
fi
if dnf repolist 2>/dev/null | grep -qw crb; then
    ok "CRB 已启用"
else
    bad "CRB 未启用（不致命，但部分 EPEL 包装不上）"
fi

# ---------------------------------------------------------------------
# 3. 装 EPEL 并把 EPEL 源也换成阿里云
#    EPEL = Extra Packages for Enterprise Linux，官方源里没有的工具
#    （htop、ncdu、jq 之类）都在这里。装法：
#      先试 dnf install epel-release（Rocky 的 extras 源里就有）
#      装不上就直接从阿里云下 epel-release-latest-<主版本>.noarch.rpm
# ---------------------------------------------------------------------
say "3. 安装并切换 EPEL 源 → 阿里云"
if ! rpm -q epel-release >/dev/null 2>&1; then
    dnf install -y epel-release >/dev/null 2>&1 \
        || dnf install -y "${EPEL_MIRROR}/epel-release-latest-${MAJOR}.noarch.rpm" >/dev/null 2>&1
fi
rpm -q epel-release >/dev/null 2>&1 && ok "epel-release 已安装" || bad "epel-release 安装失败，检查网络"

for f in /etc/yum.repos.d/epel*.repo; do
    [ -e "$f" ] || continue
    sed -i \
        -e 's|^metalink=|#metalink=|g' \
        -e 's|^#baseurl=|baseurl=|g' \
        -e "s|https://download.example/pub/epel|$EPEL_MIRROR|g" \
        -e "s|http://download.example/pub/epel|$EPEL_MIRROR|g" \
        -e 's|https://download.fedoraproject.org/pub/epel|https://mirrors.aliyun.com/epel|g' \
        -e 's|http://mirrors.aliyun.com|https://mirrors.aliyun.com|g' \
        "$f"
done

# epel-testing / epel-next 是测试分支和下一个大版本的包，不稳定，本项目用不到，关掉
for f in /etc/yum.repos.d/epel-testing*.repo /etc/yum.repos.d/epel-next*.repo; do
    [ -e "$f" ] && sed -i 's/^enabled=1/enabled=0/' "$f"
done

if grep -q "$EPEL_MIRROR" /etc/yum.repos.d/epel*.repo 2>/dev/null; then
    ok "EPEL 源已指向阿里云"
    grep -h '^baseurl=' /etc/yum.repos.d/epel.repo 2>/dev/null | sort -u | sed 's/^/         /'
else
    bad "EPEL 源替换未生效"
fi

# ---------------------------------------------------------------------
# 4. 重建缓存
#    换了源地址，旧的元数据就作废了，必须 clean + makecache 重新拉一次索引
# ---------------------------------------------------------------------
say "4. 清理并重建缓存（计时）"
dnf clean all >/dev/null 2>&1
START=$(date +%s)
if dnf makecache >/dev/null 2>&1; then
    ok "缓存重建成功，耗时 $(( $(date +%s) - START )) 秒"
else
    bad "缓存重建失败，下面是详细报错："
    dnf makecache 2>&1 | tail -15 | sed 's/^/         /'
fi

# ---------------------------------------------------------------------
# 5. 验收：光看 repolist 不够，真的装两个包才算数
#    tree 来自 baseos（验证官方源），htop 来自 epel（验证扩展源）
# ---------------------------------------------------------------------
say "5. 验证"
echo "--- dnf repolist ---"
dnf repolist 2>/dev/null | sed 's/^/    /'

echo
info "测试 1/2：从 base 源装一个包（tree）"
if dnf install -y tree >/dev/null 2>&1 && command -v tree >/dev/null 2>&1; then
    ok "base 源可用（tree 装好了）"
else
    bad "base 源装包失败"
    dnf install -y tree 2>&1 | tail -8 | sed 's/^/         /'
fi

info "测试 2/2：从 EPEL 源装一个包（htop）"
if dnf install -y htop >/dev/null 2>&1 && command -v htop >/dev/null 2>&1; then
    ok "EPEL 源可用（htop 装好了）"
else
    bad "EPEL 源装包失败"
    dnf install -y htop 2>&1 | tail -8 | sed 's/^/         /'
fi

say "完成"
info "如果上面两个测试都是 [OK]，这台机器就换源成功了。"
info "回滚方法：cp -a $BACKUP_DIR/*.repo /etc/yum.repos.d/ && dnf clean all && dnf makecache"
