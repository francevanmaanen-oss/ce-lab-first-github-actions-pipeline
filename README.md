# Lab M5.01 - First GitHub Actions Pipeline

## What This Repository Does
Demonstrates a GitHub Actions CI pipeline for Terraform that automatically
runs formatting checks, validation, and planning on every push and pull request.

## Pipeline Steps
1. **Checkout** — clones the repository
2. **Setup Terraform** — installs Terraform 1.6.0
3. **Format Check** — runs `terraform fmt -check`
4. **Init** — initializes providers (no backend)
5. **Validate** — checks configuration syntax

## Terraform Resources
- S3 bucket with versioning, encryption, and public access block
- Lifecycle rules for cost optimization (feature branch)

## How to Use

```bash
# Clone and init
git clone <your-repo-url>
cd ce-lab-first-github-actions-pipeline
terraform init

# Run locally
terraform fmt -check
terraform validate
```

## No Secrets Required
This pipeline runs `terraform validate` only — no AWS credentials needed in CI.
```

Push it:

```bash
git add README.md
git commit -m "Lab M5.01: Add README"
git push origin main
```

---

## Summary of All Fixes vs. Original Lab

| # | Issue in original | Fix applied |
|---|---|---|
| 1 | `random` provider missing from `required_providers` | Added `random ~> 3.0` to `required_providers` |
| 2 | `.terraform.lock.hcl` in `.gitignore` | Removed — lock file should be committed |
| 3 | `gh auth login` not mentioned | Added as Step 1 with verification |
| 4 | `terraform plan` in CI required AWS credentials/IAM | Removed plan step; `validate` is sufficient |
| 5 | Lifecycle rule missing `filter` block (AWS provider v5) | Added `filter { prefix = "" }` to lifecycle rule |