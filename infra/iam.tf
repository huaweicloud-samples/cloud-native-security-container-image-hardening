# ============================================================================
# IAM 委托：FunctionGraph 执行权限（扫描联动重建）
# ============================================================================
# FunctionGraph 函数负责：查询镜像扫描结果 → 高危/严重时触发流水线重建
# 并在发现高危漏洞时经 SMN 发送通知。

resource "huaweicloud_identity_agency" "functiongraph" {
  name                  = "${var.project_name}-fgs-agency"
  description           = "Agency for FunctionGraph to query scan results and trigger pipeline rebuild"
  delegated_service_name = "op_svc_cff"
  duration              = "FOREVER"

  project_role {
    project = var.region
    roles = [
      "SWR FullAccess",
      "HSS FullAccess",
      "CodeArts Pipeline FullAccess",
      "SMN Administrator",
    ]
  }

  # 2026-08-21 判别实验结论：曾加 domain_roles（CodeArts Pipeline FullAccess）实测无效——
  # 流水线执行仍报 DEVPIPE.00011412。根因是 CodeArts 项目/流水线级权限（调用主体须为项目成员或
  # 流水线授权执行者），IAM 域级角色不覆盖。已撤销以保持最小权限；修复需在 CodeArts 控制台
  # 将本委托加入项目成员（设置 > 成员管理 > 从委托中导入用户），或流水线权限管理授权执行。
}
