# 部署指导书

> 本文档指导在华为云上部署容器镜像加固流水线。所有命令在 Linux/macOS 终端或 Windows Git Bash 中执行。

## 1. 前置条件

- 华为云账号，且已完成实名认证；
- 账号具备以下服务的使用权限：VPC、NAT、EIP、OBS、KMS、SWR、CodeArts、FunctionGraph、HSS、SMN、LTS、IAM；
- 本机已安装 [Terraform](https://developer.hashicorp.com/terraform/downloads)（≥ 1.5）；
- 本机已安装 [Git](https://git-scm.com/)。

## 2. 环境准备

### 2.1 配置凭据

请在华为云「我的凭证」页面获取 Access Key，并在本地运行环境中配置（不写入任何文件）：

```bash
export HW_ACCESS_KEY="<你的 Access Key>"
export HW_SECRET_KEY="<你的 Secret Key>"
export HW_REGION_NAME="cn-north-4"
```

> 凭据由 IAM 用户创建；如需临时会话，可追加 `export HW_SECURITY_TOKEN="<token>"`。

### 2.2 准备函数代码包

扫描联动函数需要打包 SDK 依赖（FunctionGraph 运行时不自带）：

```bash
cd src/functions/scan_rebuild
bash build_package.sh        # 产出 scan_rebuild.zip（需本机 Python3 + pip + zip）
```

## 3. 配置 Terraform

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
```

编辑 `terraform.tfvars`，至少修改以下必填项：

| 变量 | 说明 |
|-|-|
| `region` | 部署区域（默认 cn-north-4） |
| `existing_vpc_id` | 复用已有 VPC 的 ID（**不新建** VPC，示例已填 devops-agent-5g-vpc 的 ID） |
| `existing_nat_gateway_name` | 复用已有公网 NAT 网关名称（**不新建** NAT，示例已填 devops-agent-5g-nat） |
| `build_subnet_cidr` | 本任务构建子网 CIDR（默认 10.0.4.0/24，落在已有 VPC 网段内且避开已用网段） |
| `obs_assets_bucket` | OBS 资源桶名（**全局唯一**，改后缀避免冲突） |
| `obs_logs_bucket` | OBS 日志桶名（**全局唯一**，改后缀避免冲突） |
| `notify_email` | 通知邮箱（可选，留空则不创建订阅） |

> **网络复用说明**：本实践不创建 VPC / NAT / EIP / IGW，而是复用账号内已有的
> VPC 与公网 NAT（其 SNAT 规则已覆盖整个 VPC 网段）。构建子网创建后即自动经
> 已有 NAT 出网。`build_subnet_cidr` 需落在已有 VPC CIDR 内且未被其他子网占用
> （示例 VPC 已用 10.0.1/2/3.0/24 与 10.0.101/102/103.0/24，故取 10.0.4.0/24）。

## 4. 部署

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

预期输出：资源创建完成后打印 outputs（SWR 仓库地址、流水线 ID、SMN 主题 URN、OBS 桶名、复用 VPC ID、构建子网 ID、复用 NAT ID、函数 URN）。

## 5. 部署后配置（一次性）

1. **开启 SWR 镜像不可变**：控制台 → 容器镜像服务 SWR → 组织 → 仓库 → 设置 → 开启「镜像不可变」；
2. **开启 SWR 仓库自动扫描**：控制台 → 仓库 → 设置 → 开启「自动扫描」（与 HSS 扫描联动）。

## 6. 构建加固镜像

流水线按调度（默认每周五 06:00）自动执行。如需立即构建：

1. 控制台 → CodeArts → 流水线 → 找到 `<image_name>-hardening-pipeline` → 执行；
2. 或命令行触发（需 CodeArts 凭据）：
   ```bash
   curl -X POST "https://codeartspipeline.cn-north-4.myhuaweicloud.com/v3/projects/<project_id>/pipelines/<pipeline_id>/run"
   ```

构建成功后，加固镜像以 `latest` 标签推送至 SWR 仓库。

## 7. 验证

| 验证项 | 方法 | 预期 |
|-|-|-|
| 流水线定时配置 | 控制台 → CodeArts 流水线 → 调度配置 | 每周五 06:00 已启用 |
| 镜像已构建推送 | 控制台 → SWR → 仓库 `<image_name>` | 存在 `latest` 标签镜像 |
| 镜像扫描 | 控制台 → SWR → 仓库 → 镜像版本 → 扫描 | 扫描完成，漏洞列表可查 |
| 漏洞联动重建 | 手动执行扫描联动函数（控制台 → FunctionGraph → 函数 → 测试） | 若存在高危/严重漏洞，流水线被触发重建 |
| 通知 | 触发一次构建/扫描后检查邮箱 | 收到 SMN 通知邮件（若已配置订阅） |

## 8. 清理资源

```bash
terraform destroy -auto-approve
```

> 注意：SWR 仓库如已开启镜像不可变或存在不可删除对象，销毁前需先在控制台清空仓库对象；OBS 桶已设置 `force_destroy` 可随桶删除。

## 9. 故障排查

| 现象 | 可能原因 | 处理 |
|-|-|-|
| apply 报权限不足 | 账号缺服务权限 | 联系管理员授予对应服务权限 |
| CodeArts Build 任务创建失败 | 构建步骤插件 ID 与目标环境不符 | 按 CodeArts 控制台实际插件调整 `infra/codearts.tf` 中 `steps.module_id`/`properties` |
| 函数执行失败 | 函数包缺 SDK 依赖 | 重新执行 `build_package.sh` 后重传（`infra/functions.tf` 中 code_url 指向的 OBS 对象） |
| SWR 仓库已存在 | 桶名/仓库名被占用 | 修改 `terraform.tfvars` 中命名后重试 |
| 整轮 `terraform apply` 报 `FSS.1153`（TIMER 触发器） | provider 对 ACTIVE 状态 TIMER 触发器不允 in-place 更新（已知 bug） | 定向重建绕过：`terraform apply -target=huaweicloud_obs_bucket_object.scan_function_code -target=huaweicloud_fgs_function.scan_rebuild -replace=huaweicloud_obs_bucket_object.scan_function_code -replace=huaweicloud_fgs_function.scan_rebuild`（重建函数连带重建 trigger=create，不撞 412） |
| 重打 zip 后 `apply` 报 No changes（代码未更新） | `huaweicloud_obs_bucket_object` 不重算本地文件哈希 | 同样用上面的定向 `-replace` 强传 |
| 函数触发流水线报 `DEVPIPE.00011412 权限不足` | FunctionGraph 委托无法加入 CodeArts 项目成员，`run_pipeline` 被项目级权限检查拒绝 | ① 用专用 IAM 用户身份（AK/SK 注入函数环境变量，用户加为 CodeArts 项目成员）；或 ② 改用流水线 Webhook 触发（官方推荐模式） |
| 流水线触发成功但无实际构建（run 状态 COMPLETED） | 控制台新建流水线的 job 是空壳（`uses:null`），未挂构建任务 | 在流水线「任务编排」里给 job 挂上实际构建任务 |
