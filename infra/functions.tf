# ============================================================================
# 扫描联动重建 + 通知：FunctionGraph + SMN
# ============================================================================
# 事件链路设计：
#   1) FunctionGraph 定时扫描 SWR 镜像（HSS 扫描结果），
#      发现高危/严重漏洞 → 触发流水线重建 + SMN 通知；
#   2) 镜像构建/推送成功 → SMN 通知订阅者（构建完成通知语义）。
#
# 注意：Pipeline 和 Build Task 通过 CodeArts 控制台手动配置（见 codearts.tf），
#       其 ID 在控制台创建后填入 var.pipeline_id，由本资源注入函数环境变量 PIPELINE_ID。

# ---- SMN 通知主题（构建与扫描结果通知）----
resource "huaweicloud_smn_topic" "hardening_notify" {
  name         = "${var.project_name}-hardening-notify"
  display_name = "Container hardening pipeline notifications"
  introduction = "Notifications for container image build success and critical scan findings"
}

resource "huaweicloud_smn_subscription" "email" {
  count = var.notify_email != "" ? 1 : 0

  topic_urn = huaweicloud_smn_topic.hardening_notify.id
  endpoint  = var.notify_email
  protocol  = "email"
  remark    = "Hardening pipeline notifications"
}

# ---- FunctionGraph：镜像扫描联动重建 ----
# 定时触发，查询最近镜像的 HSS 扫描结果，高危/严重则调用流水线重建。
# 函数代码位于 src/functions/scan_rebuild/（打包后上传 OBS）。

resource "huaweicloud_obs_bucket_object" "scan_function_code" {
  bucket = huaweicloud_obs_bucket.assets.bucket
  key    = "functions/scan_rebuild.zip"
  source = "../src/functions/scan_rebuild/scan_rebuild.zip"

  depends_on = [
    huaweicloud_obs_bucket.assets,
  ]
}

resource "huaweicloud_fgs_function" "scan_rebuild" {
  name        = "${var.project_name}-scan-rebuild"
  description = "Queries image scan results and triggers pipeline rebuild on high/critical findings"
  app         = "default"
  runtime     = "Python3.9"
  handler     = "scan_rebuild.handler"
  memory_size = 256
  timeout     = 120
  agency      = huaweicloud_identity_agency.functiongraph.name

  code_type = "obs"
  code_url  = "https://${huaweicloud_obs_bucket.assets.bucket}.obs.${var.region}.myhuaweicloud.com/functions/scan_rebuild.zip"

  user_data = jsonencode({
    SWR_ORG       = local.swr_organization
    SWR_REPO      = var.image_name
    PROJECT_ID    = huaweicloud_codearts_project.this.id
    SMN_TOPIC_URN = huaweicloud_smn_topic.hardening_notify.id
    REGION        = var.region
    PIPELINE_ID   = var.pipeline_id
  })

  depends_on = [
    huaweicloud_obs_bucket_object.scan_function_code,
  ]
}

# 定时触发器：每 6 小时扫描一次（schedule_type 大小写敏感，须为 "Cron"，docs/09 坑 11）
resource "huaweicloud_fgs_function_trigger" "scan_timer" {
  function_urn = huaweicloud_fgs_function.scan_rebuild.id
  type         = "TIMER"
  status       = "ACTIVE"

  event_data = jsonencode({
    name          = "scan-rebuild-timer"
    schedule_type = "Cron"
    schedule      = "0 0 */6 * * ?"
    user_event    = "trigger image scan and rebuild"
  })
}
