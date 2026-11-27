# cloud-native-security-container-image-hardening · 容器镜像加固流水线（Container Image Hardening Pipeline）

[![License: MIT No Attribution](https://img.shields.io/badge/License-MIT%20No%20Attribution-green.svg)](LICENSE)
[![HuaweiCloud](https://img.shields.io/badge/HuaweiCloud-Terraform-blue.svg)](https://www.huaweicloud.com)
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.5-purple.svg)](https://www.terraform.io)

## 1. 简介 / Overview

### 简介


基于 Terraform 在华为云上构建一套**容器镜像加固流水线**：在私网构建环境中产出经过安全加固（系统补丁 + 操作系统安全基线 + 最小化运行时）的「黄金」容器镜像，支持**定时重建**与**漏洞联动重建**，并通过消息通知将构建与扫描结果推送给订阅者。适用于需要稳定、可复现、持续安全的基础容器镜像的企业团队。

---

## 2. 目录


- [1. 简介 / Overview](#1-简介--overview)
- [2. 目录](#2-目录)
- [3. 架构图](#3-架构图)
- [4. 方案亮点](#4-方案亮点)
- [5. 涉及云服务](#5-涉及云服务)
- [6. 前置条件](#6-前置条件)
- [7. 快速开始](#7-快速开始)
- [8. 分步部署](#8-分步部署)
- [9. 使用方法 / 验证](#9-使用方法--验证)
- [10. 清理资源](#10-清理资源)
- [11. 详细说明](#11-详细说明)
- [12. 依赖](#12-依赖)
- [13. FAQ / 故障排除](#13-faq--故障排除)
- [14. 贡献指南](#14-贡献指南)
- [15. 许可证](#15-许可证)
- [16. 联系方式 / 维护者](#16-联系方式--维护者)



---

## 3. 架构图

![架构](docs/architecture.md)

核心流程：

1. **CodeArts 流水线**按调度（默认每周五 06:00）执行**加固构建**：以 `src/build/Dockerfile.hardened` 构建基础镜像，依次应用系统安全更新、操作系统安全基线、最小化运行时加固，产出加固镜像推送至 **SWR**（KMS 加密）；
2. **FunctionGraph** 每 6 小时查询 **HSS** 对 SWR 最新镜像的扫描结果，若发现**高危/严重漏洞**则自动触发流水线重建，同时经 **SMN** 通知订阅者；
3. 构建环境位于**私网子网**，经 **NAT 网关**出网拉取构建物料；子网流量经**流日志**审计至 LTS。

---

## 4. 方案亮点

- **持续安全**：定时重建 + 高危漏洞自动重建，镜像始终处于最新安全基线；
- **可复现**：加固逻辑以 Dockerfile + 组件 YAML 固化，构建结果确定性高；
- **私网构建**：构建流量从私网子网出网，不暴露构建入口；
- **全链路加密**：镜像与存储均由 KMS 密钥加密。

---

## 5. 涉及云服务

| 服务 | 用途 |
|-|-|
| VPC / 公网 NAT | 构建子网位于私网，经 NAT 出网 |
| CodeArts Pipeline / Build | 镜像构建与调度 |
| SWR | 加固镜像仓库 |
| OBS | 加固物料与日志存储 |
| DEW KMS | 加密 |
| HSS | 镜像漏洞扫描 |
| FunctionGraph | 扫描联动重建 |
| SMN | 通知 |
| LTS | 流日志 |
| IAM | 委托与权限 |

> 清理资源：请参见[清理资源](#清理资源)章节。

---

## 6. 前置条件

- 华为云账号（已实名认证），具备 OBS、KMS、SWR、CodeArts、FunctionGraph、HSS、SMN、LTS、IAM 服务权限；
- Terraform ≥ 1.5（[下载](https://developer.hashicorp.com/terraform/downloads)）；
- Git；
- 本机 Python3 + pip（用于打包函数）。

---

## 7. 快速开始

```bash
# 1. 配置凭据
export HW_ACCESS_KEY="<你的 Access Key>"
export HW_SECRET_KEY="<你的 Secret Key>"

# 2. 打包扫描联动函数
cd src/functions/scan_rebuild && bash build_package.sh

# 3. 配置并部署
cd infra
cp terraform.tfvars.example terraform.tfvars   # 修改桶名等必填项
terraform init && terraform apply -auto-approve
```

---

## 8. 分步部署

完整步骤与预期输出见 [docs/deployment-guide.md](docs/deployment-guide.md)：

1. 配置凭据（环境变量）；
2. 打包函数代码（`build_package.sh`）；
3. 修改 `terraform.tfvars`（桶名改全局唯一、通知邮箱）；
4. `terraform init` → `terraform plan` → `terraform apply`；
5. 部署后控制台开启 SWR「镜像不可变」与「自动扫描」。

---

## 9. 使用方法 / 验证

### 使用方法/验证


部署完成后，请按以下步骤验证业务功能可用：

1. **流水线调度**：CodeArts 控制台 → 流水线 → `<image_name>-hardening-pipeline` → 调度配置，确认「每周五 06:00」已启用；
2. **手动执行构建**：流水线详情页点击「执行」，等待构建成功；
3. **镜像推送**：SWR 控制台 → 组织/仓库 `<image_name>`，确认出现 `latest` 标签；
4. **漏洞扫描**：SWR 仓库 → 镜像版本 → 触发扫描，确认扫描完成且漏洞列表可查；
5. **漏洞联动重建**：FunctionGraph 控制台 → 扫描联动函数 → 测试，若存在高危/严重漏洞，流水线将被自动触发重建；
6. **通知**：若配置了 `notify_email`，触发一次构建后检查邮箱是否收到 SMN 通知。

> **请务必按上述步骤自行验证**：确认流水线可执行、镜像可构建推送、扫描与联动重建链路可用，方可视为部署成功。

---

## 10. 清理资源

```bash
cd infra
terraform destroy -auto-approve
```

SWR 仓库如已开启镜像不可变或存在对象，销毁前先在控制台清空仓库。

---

## 11. 详细说明

- 架构与组件职责：见 [docs/architecture.md](docs/architecture.md)；
- 加固内容：`src/build/Dockerfile.hardened` + `src/build/components/*.yml`；
- 扫描联动函数：`src/functions/scan_rebuild/`（HSS 扫描 → 高危触发流水线 + SMN 通知）；
- IaC 变量：`infra/variables.tf`，默认值见 `infra/terraform.tfvars.example`。

---

## 12. 依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| Terraform | >= 1.5 | 基础设施编排 |
| huaweicloud Provider | — | CodeArts / FunctionGraph / OBS / SMN / KMS 资源供给 |
| CodeArts Build | — | 私网镜像构建与加固 |
| FunctionGraph | Python 3.12 | 漏洞联动重建扫描函数 |

---

## 13. FAQ / 故障排除

### FAQ


**Q: 如何调整定时重建周期？**
A: 修改 FunctionGraph 定时触发器的 cron 表达式后 `terraform apply` 生效。

**Q: 加固基线如何更新？**
A: 更新构建源码中的基线脚本并推送到 CodeArts 仓库，下次构建自动采用新基线。

---

## 14. 贡献指南

欢迎提交 Issue 与 Pull Request。修改加固逻辑或构建脚本时请说明对应的安全基线依据；基础设施变更需通过 `terraform validate` 并同步更新 `docs/` 文档。

---

## 15. 许可证

本实践采用 [MIT No Attribution](LICENSE) 许可证（Copyright Huawei Cloud）。

---

## 16. 联系方式 / 维护者
| 项 | 内容 |
|---|---|
| **创建者** | [dgc-git](https://github.com/dgc-git) |
| **维护者** | [dgc-git](https://github.com/dgc-git) |
| **联系方式** | GitHub Issues / PR（见[第 14 节](#14-贡献指南)） |
