# 云原生 CI/CD 实战项目（4 VM Lab）

> 配套归档仓库。完整施工手册见 [`docs/云原生CI-CD实战项目-10天施工计划.html`](docs/云原生CI-CD实战项目-10天施工计划.html)，架构图见 [`docs/云原生CI-CD架构图.html`](docs/云原生CI-CD架构图.html)。

## 项目是什么
在 4 台 Rocky Linux 10.2 虚拟机上，从零搭建一套「代码提交 → 自动构建 → 推送镜像 → 滚动上线」的 CI/CD 实战环境，并接入监控告警。目标：提交后 3 分钟内自动上线，作为面试 / 作品集素材。

## 机器角色
| 主机 | IP | 角色 |
|------|-----|------|
| A | 192.168.80.10 | Jenkins（CI 引擎）+ kubectl |
| B | 192.168.80.20 | K8s master + Harbor（私有镜像仓库） |
| C | 192.168.80.21 | K8s worker1 |
| D | 192.168.80.22 | K8s worker2 + 外层 Nginx（统一入口） |

## 目录结构
```
app/          CI/CD 目标程序（Python Flask 待办应用）+ Dockerfile + 备份脚本
jenkins/      Jenkinsfile（五阶段流水线：拉取→静态检查→构建→推 Harbor→更新 K8s）
k8s/          Day6 资源清单（已脱敏）、带注释版、ingress-nginx 官方完整版 manifest
infra/        换源脚本、containerd/docker 镜像配置、Harbor 自签证书生成、Harbor 配置样例
monitoring/   Grafana 看板 JSON（315 / 3119）
docs/         10 天施工手册、架构图、需求与实施说明书
```

## 技术栈
Jenkins 2.580.1（JDK21） · Kubernetes v1.32 · containerd · Harbor v2.15 · ingress-nginx · Prometheus + Grafana（kube-prometheus-stack） · 外层 Nginx 反代

## 请求链路
`浏览器/用户` → `D 机 Nginx :80（按域名反代）` → `ingress-nginx NodePort` → `Service` → `Pod`
（Harbor / Grafana / todo 均通过 Ingress + 外层 Nginx 暴露；Dashboard 走 NodePort）

## 安全说明（重要）
本仓库**已脱敏**：
- `k8s/day6-todo.yaml` 与 `app/mysql_backup.sh` 中的数据库密码已替换为占位符（`<db_password>` / `<mysql_root_password>`）。
- VM root 密码、GitHub PAT、Harbor 密码、真实 kubeconfig 等**均不入库**。

实际部署请使用强密码，并通过 Kubernetes Secret / 环境变量注入，不要把明文写进清单。

## 关联仓库
- 应用源码（亦见本仓 `app/`）：https://github.com/stupidxiongxiong/todo-app （public）
