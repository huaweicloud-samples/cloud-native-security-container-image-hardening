# ============================================================================
# 容器镜像加固流水线 · Terraform 主入口
# ============================================================================
# 在私网构建环境中，基于加固 Dockerfile 构建容器镜像并推送至 SWR，
# 通过流水线定时重建 + 镜像扫描联动重建，保证镜像持续处于安全基线。
# ============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "~> 1.70"
    }
  }

  # 生产环境建议将状态文件存放到 OBS 桶（后端），按团队 state 管理规范配置。
}

# ============================================================================
# Provider 配置（AK/SK 由部署者在本地运行环境配置，不写入文件）
#   export HW_ACCESS_KEY="your-access-key"
#   export HW_SECRET_KEY="your-secret-key"
# ============================================================================

provider "huaweicloud" {
  region = var.region
}

# 当前账号项目信息（用于 CodeArts 项目归属）
data "huaweicloud_identity_projects" "current" {
  name = var.region
}

locals {
  core_tags = {
    ManagedBy   = "Terraform"
    Project     = var.project_name
    Environment = "hardening"
  }

  # SWR 组织名（镜像仓库命名空间）
  swr_organization = var.swr_organization != "" ? var.swr_organization : var.project_name
}
