# -*- coding: utf-8 -*-
"""
Push src/ directory contents to CodeArts (CodeHub) repository using AK/SK.
Uses CodeHub v3 SDK (apig-auth-iam -> supports AK/SK signing).
API: POST /v2/projects/{repo_id}/repository/commits
"""
import base64
import os
import sys

# 禁用代理，直连华为云 API
os.environ.pop("HTTP_PROXY", None)
os.environ.pop("HTTPS_PROXY", None)
os.environ.pop("http_proxy", None)
os.environ.pop("https_proxy", None)
os.environ["NO_PROXY"] = "*"
os.environ["no_proxy"] = "*"

from huaweicloudsdkcore.auth.credentials import BasicCredentials
from huaweicloudsdkcodehub.v3 import CodeHubClient, CreateCommitRequest, CreateCommitRequestBody, CommitAction

# ============ Config ============
AK = os.environ.get("HW_ACCESS_KEY", "")
SK = os.environ.get("HW_SECRET_KEY", "")
REGION = os.environ.get("HW_REGION_ID", "cn-north-4")
REPO_ID = os.environ.get("CODEHUB_REPO_ID", "")  # numeric repository_id
REPO_ID_INT = int(REPO_ID) if REPO_ID else None
BRANCH = os.environ.get("CODEHUB_BRANCH", "master")
ENDPOINT = "https://codehub-ext.cn-north-4.myhuaweicloud.com"
# ================================

SRC_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "src"))
FILES_TO_PUSH = [
    ".cloudbuild/build.yml",
    "build/Dockerfile.hardened",
    "build/components/01-system-update.yml",
    "build/components/02-baseline-hardening.yml",
    "build/components/03-minimal-runtime.yml",
    "functions/scan_rebuild/build_package.sh",
    "functions/scan_rebuild/requirements.txt",
    "functions/scan_rebuild/scan_rebuild.py",
]

def read_b64(relpath):
    full = os.path.join(SRC_ROOT, relpath.replace("/", os.sep))
    with open(full, "rb") as f:
        raw = f.read()
    return base64.b64encode(raw).decode("ascii")

def main():
    if not AK or not SK or not REPO_ID_INT:
        print("ERROR: Set HW_ACCESS_KEY, HW_SECRET_KEY and CODEHUB_REPO_ID env vars")
        sys.exit(1)

    creds = BasicCredentials(AK, SK)
    client = CodeHubClient.new_builder() \
        .with_credentials(creds) \
        .with_endpoint(ENDPOINT) \
        .build()

    actions = []
    for rel in FILES_TO_PUSH:
        full = os.path.join(SRC_ROOT, rel.replace("/", os.sep))
        if not os.path.exists(full):
            print(f"  SKIP missing: {rel}")
            continue
        actions.append(
            CommitAction(
                action="create",
                file_path=rel,
                content=read_b64(rel),
                encoding="base64",
            )
        )
        print(f"  + {rel} ({os.path.getsize(full)} bytes)")

    print(f"\nTotal files to create: {len(actions)}")

    body = CreateCommitRequestBody(
        branch=BRANCH,
        commit_message="Initial import: container hardening pipeline build sources",
        actions=actions,
        author_name="terraform-migration",
        author_email="terraform-migration@huaweicloud.com",
        stats=True,
    )
    req = CreateCommitRequest(repo_id=REPO_ID_INT, body=body)

    print(f"Creating commit on branch '{BRANCH}' of repo {REPO_ID_INT}...")
    resp = client.create_commit(req)
    print("SUCCESS:", resp.to_json_string())

if __name__ == "__main__":
    main()