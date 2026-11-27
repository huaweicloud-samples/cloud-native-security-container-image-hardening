# ============================================================================
# 输出
# ============================================================================

output "swr_repository" {
  description = "SWR 镜像仓库地址（组织/仓库名）"
  value       = "${local.swr_organization}/${var.image_name}"
}

output "smn_topic_urn" {
  description = "SMN 通知主题 URN"
  value       = huaweicloud_smn_topic.hardening_notify.id
}

output "obs_assets_bucket" {
  description = "OBS 资源桶名"
  value       = huaweicloud_obs_bucket.assets.bucket
}

output "vpc_id" {
  description = "自建 VPC ID"
  value       = huaweicloud_vpc.this.id
}

output "build_subnet_id" {
  description = "本任务构建子网 ID"
  value       = huaweicloud_vpc_subnet.hardening_pipeline_private.id
}

output "nat_gateway_id" {
  description = "自建公网 NAT 网关 ID"
  value       = huaweicloud_nat_gateway.this.id
}

output "nat_eip_address" {
  description = "NAT 出网 EIP 地址"
  value       = huaweicloud_vpc_eip.nat.address
}

output "scan_function_urn" {
  description = "扫描联动 FunctionGraph 函数 URN"
  value       = huaweicloud_fgs_function.scan_rebuild.id
}

output "codearts_project_id" {
  description = "CodeArts 项目 ID（构建任务需手动配置）"
  value       = huaweicloud_codearts_project.this.id
}
