# -*- coding: utf-8 -*-
"""Update build/Dockerfile.hardened in CodeArts repo (fix sysctl.d dir issue)."""
import base64
import os
import sys

os.environ.pop("HTTP_PROXY", None)
os.environ.pop("HTTPS_PROXY", None)
os.environ.pop("http_proxy", None)
os.environ.pop("https_proxy", None)
os.environ["NO_PROXY"] = "*"
os.environ["no_proxy"] = "*"

from huaweicloudsdkcore.auth.credentials import BasicCredentials
from huaweicloudsdkcodehub.v3 import CodeHubClient, CreateCommitRequest, CreateCommitRequestBody, CommitAction

AK = os.environ["HW_ACCESS_KEY"]
SK = os.environ["HW_SECRET_KEY"]
REPO_ID = int(os.environ["CODEHUB_REPO_ID"])
BRANCH = os.environ.get("CODEHUB_BRANCH", "master")
ENDPOINT = "https://codehub-ext.cn-north-4.myhuaweicloud.com"

SRC_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "src"))
TARGET = "build/Dockerfile.hardened"

def main():
    full = os.path.join(SRC_ROOT, TARGET.replace("/", os.sep))
    with open(full, "rb") as f:
        content = base64.b64encode(f.read()).decode("ascii")

    creds = BasicCredentials(AK, SK)
    client = CodeHubClient.new_builder() \
        .with_credentials(creds) \
        .with_endpoint(ENDPOINT) \
        .build()

    action = CommitAction(
        action="update",
        file_path=TARGET,
        content=content,
        encoding="base64",
    )
    body = CreateCommitRequestBody(
        branch=BRANCH,
        commit_message="fix: mkdir -p /etc/sysctl.d before writing hardening conf",
        actions=[action],
        author_name="terraform-migration",
        author_email="terraform-migration@huaweicloud.com",
    )
    req = CreateCommitRequest(repo_id=REPO_ID, body=body)
    resp = client.create_commit(req)
    print("SUCCESS:", resp.to_json_string()[:500])

if __name__ == "__main__":
    main()