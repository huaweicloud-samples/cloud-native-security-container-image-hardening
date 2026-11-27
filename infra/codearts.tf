# ============================================================================
# CodeArts 项目
# ============================================================================
# 构建任务（Build Task）和流水线（Pipeline）需通过 CodeArts 控制台手动配置，
# 因为：
#   1) docker_build 构建步骤模块已下架（DEVCB.00031088）
#   2) Terraform provider 不支持 code-based build（build.yml）的参数化创建
#   3) 控制台操作更直观，后续维护更方便
#
# 手动配置步骤：
#   1. 进入 CodeArts 项目 "container-hardening"
#   2. 持续交付 > 编译构建 > 新建任务
#   3. 配置构建步骤：Dockerfile 构建 + 推送 SWR
#   4. 持续交付 > 流水线 > 新建流水线
#   5. 添加构建任务触发 + 定时重建（周五 06:00）

resource "huaweicloud_codearts_project" "this" {
  name        = var.codearts_project_name
  type        = "scrum"
  description = "Container image hardening pipeline project"
}

# ---- CodeArts 代码仓库（用于承载构建源码）----
# 构建任务需要引用代码仓库中的 build.yml / Dockerfile.hardened / components
resource "huaweicloud_codearts_repository" "hardening_src" {
  name        = "${var.project_name}-src"
  description = "Container hardening pipeline build sources"
  project_id  = huaweicloud_codearts_project.this.id

  depends_on = [
    huaweicloud_codearts_project.this,
  ]
}
