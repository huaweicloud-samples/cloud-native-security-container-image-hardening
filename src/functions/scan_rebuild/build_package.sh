#!/usr/bin/env bash
# ============================================================================
# FunctionGraph 函数打包脚本
# ============================================================================
# 用途：将 scan_rebuild 函数代码 + SDK 依赖打包为 scan_rebuild.zip，
#      供 infra/functions.tf 上传至 OBS 部署。
# 用法：bash build_package.sh
# 产物：scan_rebuild.zip（与 scan_rebuild.py 同目录）
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIP_OUT="$SCRIPT_DIR/scan_rebuild.zip"

# 1. 安装依赖到临时目录（过滤 pycache，docs/09：空包/缺依赖会静默崩溃）
VENV_TMP="$(mktemp -d)"
trap 'rm -rf "$VENV_TMP"' EXIT

python3 -m pip install -r "$SCRIPT_DIR/requirements.txt" --target "$VENV_TMP" --no-cache-dir -q

# 2. 拷贝函数代码
cp "$SCRIPT_DIR/scan_rebuild.py" "$VENV_TMP/"

# 3. 打包（排除 __pycache__）
(cd "$VENV_TMP" && find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true)
(cd "$VENV_TMP" && zip -rq "$ZIP_OUT" .)

echo "[OK] 打包完成: $ZIP_OUT ($(du -h "$ZIP_OUT" | cut -f1))"
