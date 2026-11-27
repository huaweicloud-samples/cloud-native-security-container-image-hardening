# ============================================================================
# 镜像仓库：SWR
# ============================================================================

# SWR 组织（命名空间）
resource "huaweicloud_swr_organization" "this" {
  name = local.swr_organization
}

# SWR 仓库：存储加固后的容器镜像
resource "huaweicloud_swr_repository" "hardening_pipeline" {
  organization = huaweicloud_swr_organization.this.name
  name         = var.image_name
  description  = "Hardened base container image produced by the hardening pipeline"
  is_public    = false
  # 钉回线上已部署值，避免脏 state（旧 provider 写入 "other"）在本次 apply 被误改回 null
  category     = "other"

  depends_on = [
    huaweicloud_swr_organization.this
  ]
}

# HSS 镜像批量扫描（镜像推送后漏洞扫描）
# 由 FunctionGraph 定时触发，扫描 SWR 内最新镜像并按严重级别联动重建。
# 扫描结果经 SMN 通知；高危/严重级发现触发流水线重建（见 functions.tf）。
resource "huaweicloud_hss_image_batch_scan" "this" {
  count = var.image_scan_enabled ? 1 : 0

  image_type = "private_image"

  depends_on = [
    huaweicloud_swr_repository.hardening_pipeline
  ]
}
