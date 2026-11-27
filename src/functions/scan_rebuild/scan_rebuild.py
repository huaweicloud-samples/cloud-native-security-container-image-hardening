# -*- coding: utf-8 -*-
"""
镜像扫描联动重建函数（FunctionGraph）

职责：
  1. 查询 SWR 仓库最新镜像的 HSS 安全扫描结果；
  2. 若存在高危（High）/严重（Critical）漏洞，触发 CodeArts 流水线重建加固镜像；
  3. 通过 SMN 发送通知给订阅者。

触发方式：TIMER 定时触发器（默认每 6 小时），也可由控制台手动调用。

环境变量（由 Terraform user_data 注入）：
  SWR_ORG       SWR 组织名
  SWR_REPO      SWR 仓库名（镜像名）
  PIPELINE_ID   CodeArts 流水线 ID
  PROJECT_ID    CodeArts 项目 ID
  SMN_TOPIC_URN SMN 通知主题 URN
  REGION        华为云区域

凭据：由 FunctionGraph 委托（agency）提供临时凭证，无需硬编码。
"""

import json
import os

# 华为云 SDK 依赖（打包时随 zip 上传，见 build_package.sh）
from huaweicloudsdkcore.auth.credentials import BasicCredentials
from huaweicloudsdkcore.exceptions import exceptions
# 各服务 SDK 内置 region 对象：自动携带正确端点 + 可经 region 名解析 IAM 项目 ID
# （docs/09：用自定义 CoreRegion 会因 region id 无法解析项目 ID 而在 build() 崩溃；
#  CodeArts Pipeline 的正确端点域名为 cloudpipeline-ext，非 codeartspipeline）
from huaweicloudsdkhss.v5.region.hss_region import HssRegion
from huaweicloudsdkcodeartspipeline.v2.region.codeartspipeline_region import CodeArtsPipelineRegion
from huaweicloudsdksmn.v2.region.smn_region import SmnRegion

# 各服务 SDK
from huaweicloudsdkhss.v5 import HssClient, ListGeneralImageVulsRequest
from huaweicloudsdkcodeartspipeline.v2 import (
    CodeArtsPipelineClient,
    RunPipelineRequest,
    RunPipelineDTO,
)
from huaweicloudsdksmn.v2 import SmnClient, PublishMessageRequest, PublishMessageRequestBody

# 区域（cn-north-4 北京四，按实际 region 调整）；端点由 SDK 内置 region 对象提供
_REGION = os.environ.get("REGION", "cn-north-4")

_SEVERITY_MAP = {"High": "high", "Critical": "critical", "中危": "medium", "高危": "high", "严重": "critical"}


def _credentials(context):
    """从 FunctionGraph 委托(agency)获取临时 AK/SK/token。

    当前运行时(runtime)通过 context.getSecurityAccessKey() /
    getSecuritySecretKey() / getSecurityToken() 暴露委托临时凭证
    （旧版 getAccessKey()/getSecretKey() 已废弃，新版 ContextImpl 不再提供，
    直接调用会抛 AttributeError）。临时凭证为项目级(project-scoped)，
    可正确解析 HSS/SMN/CodeArts 等服务的 project_id。
    """
    ak = _ctx_cred(context, "getSecurityAccessKey", "getAccessKey")
    sk = _ctx_cred(context, "getSecuritySecretKey", "getSecretKey")
    token = _ctx_cred(context, "getSecurityToken", "getSecurityToken", required=False)
    return BasicCredentials(ak, sk).with_security_token(token)


def _ctx_cred(context, *method_names, required=True):
    """依次尝试 context 上的若干方法名，返回第一个可调用方法的返回值。"""
    for name in method_names:
        fn = getattr(context, name, None)
        if callable(fn):
            try:
                return fn()
            except Exception:
                continue
    if required:
        raise RuntimeError(
            "无法从 FunctionGraph context 获取委托临时凭证："
            "请确认函数已绑定 agency(委托) 且运行时支持 getSecurityAccessKey"
        )
    return None


def _hss_client(context):
    return HssClient.new_builder() \
        .with_credentials(_credentials(context)) \
        .with_region(HssRegion.value_of(_REGION)) \
        .build()


def _pipeline_client(context):
    return CodeArtsPipelineClient.new_builder() \
        .with_credentials(_credentials(context)) \
        .with_region(CodeArtsPipelineRegion.value_of(_REGION)) \
        .build()


def _smn_client(context):
    return SmnClient.new_builder() \
        .with_credentials(_credentials(context)) \
        .with_region(SmnRegion.value_of(_REGION)) \
        .build()


def _query_high_critical_vulns(client, project_id):
    """查询镜像仓库高危/严重漏洞数（HSS v5 ListGeneralImageVuls）。

    HSS v5 镜像漏洞接口：GET /v5/{project_id}/images/vulnerabilities
    project_id 由 SDK 凭 agency 委托(项目级)凭证自动填充 path。
    该接口必填参数：type(linux_vul/app_vul)、handle_status(unhandled/handled)、
    image_type(local/registry/cicd/cluster)。这里按 registry(仓库镜像)、未处理状态，
    分别查询 linux_vul 与 app_vul 两类漏洞并汇总高危/严重数。
    """
    total = 0
    for vul_type in ("linux_vul", "app_vul"):
        request = ListGeneralImageVulsRequest()
        request.type = vul_type
        request.handle_status = "unhandled"
        request.image_type = "registry"
        request.enterprise_project_id = "all_granted_eps"
        request.offset = 0
        request.limit = 200
        try:
            response = client.list_general_image_vuls(request)
        except exceptions.ClientRequestException as e:
            # 无漏洞/接口异常时按 0 处理，避免函数整体失败
            if e.status_code in (404, 500):
                continue
            raise
        items = getattr(response, "data_list", []) or []
        for item in items:
            sev = getattr(item, "severity_level", "")
            if isinstance(sev, dict):
                sev = sev.get("severity_level", "")
            if str(sev) in ("High", "Critical"):
                total += 1
    return total


def _trigger_pipeline(client, project_id, pipeline_id):
    """触发流水线重建加固镜像（Path: /v5/{project_id}/api/pipelines/{pipeline_id}/run）。

    注意：CodeArts Pipeline 对权限不足等业务错误会返回 HTTP 200 + 错误体，SDK 不抛异常。
    RunPipelineResponse 模型只声明 pipeline_run_id/error_msg 两个字段，error_code 仅在
    原始响应 JSON（to_json_object）里——必须基于 to_json_object 显式检查，否则会"假成功"
    （实测 DEVPIPE.00011412 权限不足曾被吞掉）。
    """
    request = RunPipelineRequest()
    request.project_id = project_id
    request.pipeline_id = pipeline_id
    request.body = RunPipelineDTO()
    response = client.run_pipeline(request)
    resp_dict = response.to_json_object() if hasattr(response, "to_json_object") else {}
    err_code = resp_dict.get("error_code")
    err_msg = getattr(response, "error_msg", None) or resp_dict.get("error_msg")
    if err_code or err_msg:
        raise RuntimeError(
            f"run_pipeline rejected by CodeArts Pipeline: {err_code or ''} {err_msg or ''}".strip()
        )
    if not getattr(response, "pipeline_run_id", None) and not resp_dict.get("pipeline_run_id"):
        raise RuntimeError("run_pipeline returned no pipeline_run_id (trigger failed unexpectedly)")
    return response


def _notify(client, topic_urn, message):
    """SMN 发送通知（与 run_pipeline 相同：防御"200+错误体"假成功模式）。"""
    request = PublishMessageRequest()
    request.topic_urn = topic_urn
    request.body = PublishMessageRequestBody(message=message)
    response = client.publish_message(request)
    resp_dict = response.to_json_object() if hasattr(response, "to_json_object") else {}
    err_code = resp_dict.get("error_code")
    err_msg = resp_dict.get("error_msg")
    if err_code or err_msg:
        raise RuntimeError(
            f"publish_message rejected by SMN: {err_code or ''} {err_msg or ''}".strip()
        )
    if not getattr(response, "message_id", None) and not resp_dict.get("message_id"):
        raise RuntimeError("publish_message returned no message_id (notification failed unexpectedly)")
    return response


def handler(event, context):
    swr_org = os.environ.get("SWR_ORG", "")
    swr_repo = os.environ.get("SWR_REPO", "")
    pipeline_id = os.environ.get("PIPELINE_ID", "")
    project_id = os.environ.get("PROJECT_ID", "")
    topic_urn = os.environ.get("SMN_TOPIC_URN", "")

    if not all([swr_org, swr_repo, pipeline_id, project_id, topic_urn]):
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "missing required environment variables"}),
        }

    hss = _hss_client(context)
    high_critical = _query_high_critical_vulns(hss, project_id)

    if high_critical > 0:
        # 高危/严重漏洞存在 → 触发流水线重建
        pipeline = _pipeline_client(context)
        _trigger_pipeline(pipeline, project_id, pipeline_id)

        # 通知订阅者
        smn = _smn_client(context)
        _notify(
            smn,
            topic_urn,
            f"[镜像加固] 仓库 {swr_org}/{swr_repo} 检测到 {high_critical} 个高危/严重漏洞，"
            f"已触发流水线重建加固镜像（pipeline: {pipeline_id}）。",
        )
        return {
            "statusCode": 200,
            "body": json.dumps({"rebuild_triggered": True, "high_critical_findings": high_critical}),
        }

    return {
        "statusCode": 200,
        "body": json.dumps({"rebuild_triggered": False, "high_critical_findings": 0}),
    }
