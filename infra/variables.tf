###################################
## 基础
###################################

variable "region" {
  type        = string
  description = "华为云区域（cn-north-4 北京四）"
  default     = "cn-north-4"
}

variable "project_name" {
  type        = string
  description = "项目名称，用于资源命名前缀与标签。"
  default     = "linux-baseline"
}

variable "image_name" {
  type        = string
  description = "加固容器镜像名称（对应 SWR 仓库名）。"
  default     = "linux-baseline"

  validation {
    condition     = can(regex("[a-zA-Z0-9-]{3,50}", var.image_name))
    error_message = "image_name 需为 3-50 位字母数字与连字符。"
  }
}

variable "vpc_name" {
  type        = string
  description = "自建 VPC 名称与构建子网命名前缀。"
  default     = "container-hardening-vpc"
}

# ---- 自建网络（VPC/NAT/EIP 全部自建，不依赖外部资源）----

variable "vpc_cidr" {
  type        = string
  description = "自建 VPC 网段（CIDR）。"
  default     = "172.16.0.0/16"
}

variable "build_subnet_cidr" {
  type        = string
  description = "构建子网 CIDR（必须落在 vpc_cidr 内且未被占用）。"
  default     = "172.16.1.0/24"
}

variable "nat_spec" {
  type        = string
  description = "公网 NAT 网关规格（1=小型，2=中型，3=大型，4=超大型）。"
  default     = "1"
}

variable "eip_bandwidth_size" {
  type        = number
  description = "NAT 出网 EIP 带宽大小（Mbit/s，按流量计费）。"
  default     = 5
}

variable "obs_assets_bucket" {
  type        = string
  description = "OBS 桶名（全局唯一），存放加固组件与构建产物。"
}

variable "obs_logs_bucket" {
  type        = string
  description = "OBS 桶名（全局唯一），存放访问日志与流日志。"
}

variable "swr_organization" {
  type        = string
  description = "SWR 组织名（命名空间）。留空则使用 project_name。"
  default     = ""
}

variable "codearts_project_name" {
  type        = string
  description = "CodeArts 项目名称。"
  default     = "container-hardening"
}

variable "schedule_enabled" {
  type        = bool
  description = "是否启用流水线定时重建。"
  default     = true
}

variable "image_scan_enabled" {
  type        = bool
  description = "是否在镜像推送后自动触发安全扫描。"
  default     = true
}

variable "notify_email" {
  type        = string
  description = "接收镜像构建/扫描通知的邮箱（SMN 订阅）。留空则不创建订阅。"
  default     = ""
}

variable "pipeline_id" {
  type        = string
  description = "CodeArts 流水线 ID。流水线在控制台手动创建后（见 codearts.tf），将其 ID 填入本变量，由函数环境变量 PIPELINE_ID 注入，用于联动触发加固镜像重建。"
  default     = ""
}
