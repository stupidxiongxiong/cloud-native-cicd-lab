#!/bin/bash
set -e
M=https://swr.cn-north-4.myhuaweicloud.com
D=https://docker.m.daocloud.io

# 1) 三套 hosts.toml：docker.io 走 Daocloud 通用代理（能拉 python/calico 等），其余走 SWR
mkdir -p /etc/containerd/certs.d/docker.io /etc/containerd/certs.d/registry.k8s.io /etc/containerd/certs.d/quay.io

cat > /etc/containerd/certs.d/docker.io/hosts.toml <<EOF
server = "https://registry-1.docker.io"

[host."$D"]
  capabilities = ["pull", "resolve"]
EOF

cat > /etc/containerd/certs.d/registry.k8s.io/hosts.toml <<EOF
server = "https://registry.k8s.io"

[host."$M"]
  capabilities = ["pull", "resolve"]
EOF

cat > /etc/containerd/certs.d/quay.io/hosts.toml <<EOF
server = "https://quay.io"

[host."$M"]
  capabilities = ["pull", "resolve"]
EOF

# 2) 关键：把 config_path 直接写进主 config.toml
#    （containerd 2.x 只有主配置写了 imports 才会读 conf.d，靠 drop-in 不可靠，Day 5 曾因此踩坑）
echo "改前 config_path："
grep -n 'config_path' /etc/containerd/config.toml || true
sed -i 's|config_path = ""|config_path = "/etc/containerd/certs.d"|' /etc/containerd/config.toml
echo "改后 config_path："
grep -n 'config_path' /etc/containerd/config.toml || true

# 3) 重启生效
systemctl restart containerd
echo "certs.d 已启用：docker.io 走 Daocloud，registry.k8s.io/quay.io 走 SWR"
echo "验收：ctr -n k8s.io i pull docker.io/library/busybox:latest 能拉到即生效"
