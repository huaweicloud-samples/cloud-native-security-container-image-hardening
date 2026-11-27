# ============================================================================
# 加密层：DEW KMS 密钥（镜像与 OBS 加密）
# ============================================================================

# 构建物料与镜像加密密钥
resource "huaweicloud_kms_key" "this" {
  key_alias       = "${var.project_name}-key"
  key_description = "Encryption key for container image hardening pipeline"
  pending_days    = "7"
  rotation_enabled = true
  is_enabled      = true

  tags = local.core_tags
}

# 密钥别名（alias/<kms_key_alias> 语义）
resource "huaweicloud_kms_alias" "this" {
  alias  = "alias/${var.project_name}"
  key_id = huaweicloud_kms_key.this.id
}
