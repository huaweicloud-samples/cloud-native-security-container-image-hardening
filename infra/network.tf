# ============================================================================
# 网络层：自建 VPC / 子网 / 公网 NAT / EIP（完全自包含，不依赖外部网络资源）
# ============================================================================
# 设计说明：
#   - 自建 VPC + 构建子网，完全隔离，不与其他任务共享网络；
#   - 自建公网 NAT 网关 + EIP，通过 SNAT 规则让构建子网出网拉取构建物料；
#   - 流日志按子网粒度采集至 LTS；
#   - terraform destroy 会一并释放 VPC / NAT / EIP / 子网 / 流日志。

# ---- 自建 VPC ----
resource "huaweicloud_vpc" "this" {
  name = var.vpc_name
  cidr = var.vpc_cidr

  tags = local.core_tags
}

# ---- 构建子网（私网）----
resource "huaweicloud_vpc_subnet" "hardening_pipeline_private" {
  name       = "${var.vpc_name}-private"
  vpc_id     = huaweicloud_vpc.this.id
  cidr       = var.build_subnet_cidr
  gateway_ip = cidrhost(var.build_subnet_cidr, 1)

  tags = local.core_tags
}

# ---- 公网 EIP（NAT 出网）----
resource "huaweicloud_vpc_eip" "nat" {
  name = "${var.project_name}-nat-eip"

  publicip {
    type = "5_bgp"
  }

  bandwidth {
    name        = "${var.project_name}-nat-eip-bw"
    size        = var.eip_bandwidth_size
    share_type  = "PER"
    charge_mode = "traffic"
  }

  tags = local.core_tags
}

# ---- 公网 NAT 网关 ----
resource "huaweicloud_nat_gateway" "this" {
  name        = "${var.project_name}-nat"
  description = "NAT gateway for container image build egress"
  spec        = var.nat_spec
  vpc_id      = huaweicloud_vpc.this.id
  subnet_id   = huaweicloud_vpc_subnet.hardening_pipeline_private.id
}

# ---- SNAT 规则：构建子网 → EIP 出网 ----
resource "huaweicloud_nat_snat_rule" "build" {
  nat_gateway_id = huaweicloud_nat_gateway.this.id
  network_id     = huaweicloud_vpc_subnet.hardening_pipeline_private.id
  source_type    = 0 # 0 = 按子网（network_id）
  floating_ip_id = huaweicloud_vpc_eip.nat.id
  description    = "Build subnet egress via NAT"
}

# ============================================================================
# 可观测：子网级流日志 → LTS（仅采集本任务子网流量）
# ============================================================================

resource "huaweicloud_lts_group" "flow_log" {
  group_name  = "${var.project_name}-flow-log"
  ttl_in_days = 30
}

resource "huaweicloud_lts_stream" "flow_log" {
  group_id    = huaweicloud_lts_group.flow_log.id
  stream_name = "${var.project_name}-subnet-flow"
}

resource "huaweicloud_vpc_flow_log" "hardening_pipeline" {
  name          = "${var.project_name}-subnet-flow-log"
  resource_id   = huaweicloud_vpc_subnet.hardening_pipeline_private.id
  resource_type = "network"
  traffic_type  = "all"
  log_group_id  = huaweicloud_lts_group.flow_log.id
  log_stream_id = huaweicloud_lts_stream.flow_log.id
}
