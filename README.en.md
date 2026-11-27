# cloud-native-security-container-image-hardening

[![License: MIT No Attribution](https://img.shields.io/badge/License-MIT%20No%20Attribution-green.svg)](LICENSE)
[![HuaweiCloud](https://img.shields.io/badge/HuaweiCloud-Terraform-blue.svg)](https://www.huaweicloud.com)
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.5-purple.svg)](https://www.terraform.io)

## 1. Overview

This practice builds a **container image hardening pipeline** on Huawei Cloud with Terraform: in a private-network build environment it produces "golden" container images that have been security-hardened (system patches + OS security baseline + minimized runtime), supports **scheduled rebuilds** and **vulnerability-triggered rebuilds**, and pushes build and scan results to subscribers through message notifications. It is intended for enterprise teams that need stable, reproducible, and continuously secure base container images.

## 2. Table of Contents

- [1. Overview](#1-overview)
- [2. Table of Contents](#2-table-of-contents)
- [3. Architecture Diagram](#3-architecture-diagram)
- [4. Highlights](#4-highlights)
- [5. Cloud Services Used](#5-cloud-services-used)
- [6. Prerequisites](#6-prerequisites)
- [7. Quick Start](#7-quick-start)
- [8. Step-by-Step Deployment](#8-step-by-step-deployment)
- [9. Usage / Verification](#9-usage--verification)
- [10. Cleanup](#10-cleanup)
- [11. Detailed Explanation](#11-detailed-explanation)
- [12. Dependencies](#12-dependencies)
- [13. FAQ / Troubleshooting](#13-faq--troubleshooting)
- [14. Contributing](#14-contributing)
- [15. License](#15-license)
- [16. Contact / Maintainers](#16-contact--maintainers)

## 3. Architecture Diagram

![Architecture](docs/architecture.md)

Core workflow:

1. **CodeArts Pipeline** runs a **hardening build** on schedule (weekly, Friday 06:00 by default): it builds the base image from `src/build/Dockerfile.hardened`, applies system security updates, the OS security baseline, and minimized-runtime hardening in sequence, and pushes the hardened image to **SWR** (encrypted with KMS);
2. **FunctionGraph** queries **HSS** scan results for the latest SWR image every 6 hours; if **high-risk / critical vulnerabilities** are found, it automatically triggers a pipeline rebuild and notifies subscribers through **SMN**;
3. The build environment sits in a **private subnet**, reaching the internet through a **NAT Gateway** to pull build materials; subnet traffic is audited to LTS through **flow logs**.

## 4. Highlights

- **Continuous security**: Scheduled rebuilds + automatic rebuilds on high-risk vulnerabilities keep images at the latest security baseline;
- **Reproducible**: Hardening logic is fixed in Dockerfile + component YAML, giving highly deterministic build results;
- **Private-network build**: Build traffic egresses from a private subnet, with no build entry point exposed;
- **Full-chain encryption**: Both images and storage are encrypted with KMS keys.

## 5. Cloud Services Used

| Service | Purpose |
|-|-|
| VPC / Public NAT | Build subnet is private, egressing through NAT |
| CodeArts Pipeline / Build | Image build and scheduling |
| SWR | Hardened image repository |
| OBS | Hardening materials and log storage |
| DEW KMS | Encryption |
| HSS | Image vulnerability scanning |
| FunctionGraph | Scan-triggered rebuilds |
| SMN | Notifications |
| LTS | Flow logs |
| IAM | Agencies and permissions |

> Cleanup: See the [Cleanup](#10-cleanup) section.

## 6. Prerequisites

- A Huawei Cloud account (real-name verified) with permissions for OBS, KMS, SWR, CodeArts, FunctionGraph, HSS, SMN, LTS, and IAM;
- Terraform >= 1.5 ([download](https://developer.hashicorp.com/terraform/downloads));
- Git;
- Python3 + pip on the local machine (for packaging functions).

## 7. Quick Start

```bash
# 1. Configure credentials
export HW_ACCESS_KEY="<your-access-key>"
export HW_SECRET_KEY="<your-secret-key>"

# 2. Package the scan-triggered rebuild function
cd src/functions/scan_rebuild && bash build_package.sh

# 3. Configure and deploy
cd infra
cp terraform.tfvars.example terraform.tfvars   # Modify required fields such as the bucket name
terraform init && terraform apply -auto-approve
```

## 8. Step-by-Step Deployment

For complete steps and expected output, see [docs/deployment-guide.md](docs/deployment-guide.md):

1. Configure credentials (environment variables);
2. Package the function code (`build_package.sh`);
3. Edit `terraform.tfvars` (make the bucket name globally unique, set the notification email);
4. `terraform init` → `terraform plan` → `terraform apply`;
5. After deployment, enable SWR "image immutability" and "automatic scan" in the console.

## 9. Usage / Verification

After deployment, verify that the business functionality works:

1. **Pipeline schedule**: CodeArts console → Pipeline → `<image_name>-hardening-pipeline` → Schedule configuration, confirm "Friday 06:00" is enabled;
2. **Manual build**: On the pipeline details page click "Execute" and wait for the build to succeed;
3. **Image push**: SWR console → organization/repository `<image_name>`, confirm the `latest` tag appears;
4. **Vulnerability scan**: SWR repository → image version → trigger a scan, confirm the scan completes and the vulnerability list is queryable;
5. **Vulnerability-triggered rebuild**: FunctionGraph console → scan-triggered function → Test; if high-risk / critical vulnerabilities exist, the pipeline is automatically triggered to rebuild;
6. **Notification**: If `notify_email` is configured, trigger a build and check whether an SMN notification arrives by email.

> **Be sure to verify using the steps above**: confirm that the pipeline is executable, the image can be built and pushed, and the scan and rebuild-trigger chain works, before considering the deployment successful.

After deployment, follow these steps to verify that the business functionality works before considering the delivery complete.

## 10. Cleanup

```bash
cd infra
terraform destroy -auto-approve
```

If the SWR repository has image immutability enabled or still contains objects, empty the repository in the console before destroying.

## 11. Detailed Explanation

- Architecture and component responsibilities: see [docs/architecture.md](docs/architecture.md);
- Hardening content: `src/build/Dockerfile.hardened` + `src/build/components/*.yml`;
- Scan-triggered rebuild function: `src/functions/scan_rebuild/` (HSS scan → high-risk triggers pipeline + SMN notification);
- IaC variables: `infra/variables.tf`, defaults in `infra/terraform.tfvars.example`.

## 12. Dependencies

| Dependency | Version | Purpose |
|------|------|------|
| Terraform | >= 1.5 | Infrastructure orchestration |
| huaweicloud Provider | — | CodeArts / FunctionGraph / OBS / SMN / KMS resource provisioning |
| CodeArts Build | — | Private-network image build and hardening |
| FunctionGraph | Python 3.12 | Vulnerability-triggered rebuild scan function |

## 13. FAQ / Troubleshooting

**Q: How do I change the scheduled rebuild interval?**
A: Modify the cron expression of the FunctionGraph timer trigger, then run `terraform apply`.

**Q: How do I update the hardening baseline?**
A: Update the baseline script in the build source and push it to the CodeArts repository; the next build automatically uses the new baseline.

## 14. Contributing

Issues and Pull Requests are welcome. When changing hardening logic or build scripts, please state the corresponding security-baseline rationale; infrastructure changes must pass `terraform validate` and update the `docs/` documentation accordingly.

## 15. License

This practice is licensed under [MIT No Attribution](LICENSE) (Copyright Huawei Cloud).

## 16. Contact / Maintainers
| Item | Content |
|---|---|
| **Creator** | [dgc-git](https://github.com/dgc-git) |
| **Maintainer** | [dgc-git](https://github.com/dgc-git) |
| **Contact** | GitHub Issues / PR (see [Section 14](#14-contributing)) |
