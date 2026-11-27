# ============================================================================
# 存储层：OBS 资源桶（构建物料）+ 日志桶（访问日志/流日志）
# ============================================================================

# 日志桶（访问日志 / 流日志）
# 注意：不开 versioning——terraform destroy 对版本化桶 force_destroy 会批量删版本报
# MalformedXML（provider bug，实测），关闭版本化可保证销毁一键成功。
resource "huaweicloud_obs_bucket" "logs" {
  bucket        = var.obs_logs_bucket
  acl           = "private"
  force_destroy = true
  encryption    = true
  kms_key_id    = huaweicloud_kms_key.this.id

  tags = local.core_tags
}

# 资源桶（存放加固组件与构建物料）
resource "huaweicloud_obs_bucket" "assets" {
  bucket        = var.obs_assets_bucket
  acl           = "private"
  force_destroy = true
  encryption    = true
  kms_key_id    = huaweicloud_kms_key.this.id

  tags = local.core_tags

  depends_on = [
    huaweicloud_obs_bucket.logs
  ]
}

# 上传加固组件文件（加固组件定义位于 src/build/components/ 下的 YAML 清单）
resource "huaweicloud_obs_bucket_object" "component_files" {
  for_each = fileset(path.module, "../src/build/components/*.yml")

  bucket  = huaweicloud_obs_bucket.assets.bucket
  key     = "components/${basename(each.value)}"
  source  = each.value
  kms_key_id = huaweicloud_kms_key.this.id

  depends_on = [
    huaweicloud_obs_bucket.assets,
    huaweicloud_kms_key.this,
  ]
}

# 上传加固 Dockerfile（构建流水线消费）
resource "huaweicloud_obs_bucket_object" "dockerfile" {
  bucket = huaweicloud_obs_bucket.assets.bucket
  key    = "build/Dockerfile.hardened"
  source = "../src/build/Dockerfile.hardened"
  kms_key_id = huaweicloud_kms_key.this.id

  depends_on = [
    huaweicloud_obs_bucket.assets,
    huaweicloud_kms_key.this,
  ]
}
