# Day 7 故障修复手册：ingress-nginx 镜像离线导入

## 一、问题根因（已实测确认）

- 你把 `registry.k8s.io` sed 改成了 `k8s.m.daocloud.io`，但该源从 VM **拉不到**（manifest 直接 502，blob 存储 `r2.daocloud.vip` 连接超时）。
- VM 上所有镜像源实测结论：
  - `k8s.m.daocloud.io` → 可达但 **502**
  - 华为 SWR (`swr.cn-north-4.myhuaweicloud.com`) → 可达但 **404**（只缓存 pause 等极少数核心镜像，**没有 ingress-nginx**）
  - `registry.aliyuncs.com` → 可达，但 **只有 `kube-webhook-certgen`、没有 `ingress-nginx-controller`**
  - Docker Hub 直连 → **000 被墙**
  - `registry.k8s.io` 直连 → 连接拒绝（被墙）
- **结论**：controller 镜像在 VM 上无可达源 → 必须 **Windows 离线导入**（Windows 有外网）。

## 二、修复总览（4 步）

1. Windows 拉原版镜像并 `save` 成 tar
2. scp 到 3 台节点，`ctr -n k8s.io images import`
3. 把 manifest 里的 `k8s.m.daocloud.io` 改回 `registry.k8s.io`
4. `delete -f` + `apply -f` 重建并验收

## 三、详细步骤（可勾选）

### 步骤 A：Windows 拉镜像（两种方法选一种）

**方法 1：Docker Desktop（若已装）**

```bash
docker pull registry.k8s.io/ingress-nginx/controller:v1.12.7@sha256:6ca5f62d18ac6b2e57484ecde310dccd3079b545acecff01c4c71eb5fb222438
docker pull registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.3@sha256:3d671cf20a35cd94efc5dcd484970779eb21e7938c98fbc3673693b8a117cf39
docker save -o ingress-nginx.tar registry.k8s.io/ingress-nginx/controller:v1.12.7 registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.3
```

**方法 2：WSL2 + skopeo（没 Docker 时用）**

```bash
skopeo copy docker://registry.k8s.io/ingress-nginx/controller@sha256:6ca5f62d18ac6b2e57484ecde310dccd3079b545acecff01c4c71eb5fb222438 docker-archive:/mnt/c/Users/one/ingress-nginx-controller.tar:registry.k8s.io/ingress-nginx/controller:v1.12.7
skopeo copy docker://registry.k8s.io/ingress-nginx/kube-webhook-certgen@sha256:3d671cf20a35cd94efc5dcd484970779eb21e7938c98fbc3673693b8a117cf39 docker-archive:/mnt/c/Users/one/ingress-nginx-webhook.tar:registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.3
```

### 步骤 B：传送到 3 台节点并导入（每台都做）

Windows 侧（Git Bash / PowerShell）把 tar 传过去：

```bash
scp ingress-nginx.tar root@192.168.80.20:/root/
scp ingress-nginx.tar root@192.168.80.21:/root/
scp ingress-nginx.tar root@192.168.80.22:/root/
```

在**每台节点**上导入（注意命名空间是 `k8s.io`）：

```bash
ctr -n k8s.io images import /root/ingress-nginx.tar
# 校验：应看到带 @sha256: 的两行
ctr -n k8s.io images ls | grep ingress-nginx
```

> 用 skopeo 方法则分别传两个 tar，每台执行两次 `ctr -n k8s.io images import <对应tar>`。

### 步骤 C：修正 manifest（在 master B 上）

```bash
sed -i 's#k8s.m.daocloud.io#registry.k8s.io#g' /root/ingress-nginx.yaml
grep -n 'image' /root/ingress-nginx.yaml   # 确认 3 处都变回 registry.k8s.io
```

### 步骤 D：删旧重建 + 验收

```bash
kubectl delete -f /root/ingress-nginx.yaml      # 清掉失败的 admission Job（它们不会自动重跑）
kubectl apply  -f /root/ingress-nginx.yaml
kubectl get pods -n ingress-nginx -w             # 等到 controller Running、两个 admission Job Completed
kubectl get svc  -n ingress-nginx               # 记下 NodePort（本次实测 31534/HTTP、32144/HTTPS）
```

## 四、踩坑提醒

- ⚠️ `ingress-nginx-admission-create` / `-patch` 两个 Job 失败后**不会自动重跑**，必须 `delete -f` 再 `apply` 才能重建。
- ⚠️ NodePort 端口是**系统自动分配**，每次可能不同，别死记 30080/30443，以 `kubectl get svc` 实际输出为准。之后外层 Nginx 的 `proxy_pass` 要用这个实际端口。
- ⚠️ 导入用 `ctr -n k8s.io`（K8s 用的 containerd 命名空间是 `k8s.io`），不是默认命名空间，否则 kubelet 找不到。
- 顺带更正 Day 5 记忆：SWR 加速 **必须带 `/ddn-k8s/registry.k8s.io/` 前缀**才有效，且**不含 ingress-nginx**；之前"根路径直出、无需前缀"是错的。
