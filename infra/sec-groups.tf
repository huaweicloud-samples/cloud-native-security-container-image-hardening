# ============================================================================
# 安全组：镜像构建环境安全组
# ============================================================================
# 构建流量从私网子网经 NAT 出网（仅出站），
# 入站仅开放 HTTPS 与临时端口用于拉取构建物料。

resource "huaweicloud_networking_secgroup" "image_builder_sg" {
  name        = "${var.image_name}-sg"
  description = "Security group for container image build environment"
}

# HTTPS 入站（拉取构建物料 / 仓库认证）
resource "huaweicloud_networking_secgroup_rule" "allow_https" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.image_builder_sg.id
}

# 临时端口入站（覆盖 1025-65535）
resource "huaweicloud_networking_secgroup_rule" "allow_ephemeral" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1025
  port_range_max    = 65535
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.image_builder_sg.id
}

# 注：出站默认全放行（安全组默认 egress allow-all，无需显式规则）
