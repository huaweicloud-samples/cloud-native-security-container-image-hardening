#!/usr/bin/env python3
# 重建 scan_rebuild.zip：源码 + 钉定版华为云 SDK 依赖（自包含，FunctionGraph 运行期可直接 import）
import os, sys, subprocess, zipfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
VENV_PIP = r"C:/Users/dgcd/.workbuddy/binaries/python/envs/default/Scripts/python.exe"
DEPS = os.path.join(HERE, "_deps_build")
ZIP_PATH = os.path.join(HERE, "scan_rebuild.zip")
REQS = os.path.join(HERE, "requirements.txt")

# 1) 安装依赖到 _deps_build（已装则跳过）
if not os.path.isdir(os.path.join(DEPS, "huaweicloudsdkcore")):
    os.makedirs(DEPS, exist_ok=True)
    subprocess.check_call([VENV_PIP, "-m", "pip", "install",
                           "-r", REQS, "--target", DEPS, "--quiet",
                           "--upgrade", "--force-reinstall"])

# 2) 打包：源码 .py + _deps_build 全部内容（扁平放入 zip 根，保证 import 路径正确）
with zipfile.ZipFile(ZIP_PATH, "w", zipfile.ZIP_DEFLATED) as z:
    # 源码
    for f in os.listdir(HERE):
        if f.endswith(".py") and f != "_build_zip.py":
            z.write(os.path.join(HERE, f), f)
    # 依赖
    for root, dirs, files in os.walk(DEPS):
        # 跳过无关元数据（减小体积，非必须）
        if "dist-info" in root or "METADATA" in root:
            pass
        for fn in files:
            full = os.path.join(root, fn)
            rel = os.path.relpath(full, DEPS)
            z.write(full, rel)

print("built", ZIP_PATH, os.path.getsize(ZIP_PATH), "bytes")
