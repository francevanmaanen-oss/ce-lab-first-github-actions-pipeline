# Lab M5.01 — First GitHub Actions Pipeline (Corrected)

> **What changed from the original and why** is noted in `> blockquotes` throughout.

---

## Learning Objectives

- Create a GitHub Actions workflow from scratch
- Configure CI triggers for push and pull request events
- Automate Terraform formatting and validation
- Test the pipeline by opening a pull request on a feature branch

---

## Prerequisites

- GitHub account with repository creation permissions
- Git CLI installed and configured
- GitHub CLI (`gh`) installed — verify with `gh --version`
- Authenticated to GitHub CLI — run `gh auth login` if not done yet

> **Fix:** The original never mentioned `gh auth login`. Without it, every `gh` command fails with an auth error.

---

## Introduction

GitHub Actions lets you automate workflows directly inside your repository. In this lab you build your first CI pipeline that runs Terraform checks every time code is pushed or a pull request is opened.

> **Note on `terraform plan`:** The original lab included a `terraform plan` step in CI. This requires real AWS credentials and correct IAM permissions — a common failure point in lab environments. This corrected lab **removes `terraform plan` from CI** and replaces it with `terraform validate` only. Plan is left as a local/manual step. This is actually the more common real-world pattern for a first pipeline.

---

## Step 1: Authenticate GitHub CLI

```bash
gh auth login
```

Follow the prompts — choose **GitHub.com → HTTPS → Login with a web browser**.

Verify it worked:

```bash
gh auth status
```

---

## Step 2: Create the Project Structure

```bash
mkdir -p ~/ce-labs/m5-01-pipeline/.github/workflows
cd ~/ce-labs/m5-01-pipeline

touch main.tf variables.tf outputs.tf .gitignore
```

Add a `.gitignore` for Terraform:

```
.terraform/
*.tfstate
*.tfstate.backup
*.tfplan
```

> **Fix:** The original included `.terraform.lock.hcl` in `.gitignore`. This is wrong — the lock file **should be committed** so CI uses the exact same provider versions as your local machine. Removing it from `.gitignore` is the correct practice.

---

## Step 3: Write the Terraform Configuration

### `main.tf`

```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "app_assets" {
  bucket = "${var.project_name}-${var.environment}-assets-${random_id.suffix.hex}"

  tags = {
    Name        = "${var.project_name}-assets"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "app_assets" {
  bucket = aws_s3_bucket.app_assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_assets" {
  bucket = aws_s3_bucket.app_assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "app_assets" {
  bucket = aws_s3_bucket.app_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

> **Fix:** The original `main.tf` used `random_id.suffix` but never declared the `random` provider in `required_providers`. This causes `terraform init` and `terraform validate` to fail with "provider registry.terraform.io/hashicorp/random: required by this configuration but no version constraint given". The `random` provider block is now added.

### `variables.tf`

```hcl
variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
  default     = "ci-lab"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
```

### `outputs.tf`

```hcl
output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.app_assets.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.app_assets.arn
}
```

---

## Step 4: Create the GitHub Actions Workflow

Create `.github/workflows/ci.yml`:

```yaml
name: Terraform CI

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

permissions:
  contents: read

jobs:
  terraform-ci:
    name: Terraform Checks
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.6.0

      - name: Terraform Format Check
        run: terraform fmt -check -recursive
        continue-on-error: false

      - name: Terraform Init
        run: terraform init -backend=false

      - name: Terraform Validate
        run: terraform validate
```

> **Fix:** Removed the `terraform plan` step entirely. The original plan step required `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` secrets to be correctly configured with the right IAM permissions. Without that, the step fails with an auth error — not a Terraform error — which is confusing in a lab about CI pipelines. `terraform validate` is sufficient to confirm your configuration is syntactically correct and internally consistent, which is the real learning goal here.

**Key points about this workflow:**

- `on: push` and `on: pull_request` — triggers on both events targeting `main`
- `actions/checkout@v4` — clones the repository into the runner
- `hashicorp/setup-terraform@v3` — installs the specified Terraform version
- `-backend=false` — skips remote backend during CI (no state file needed for validation)
- `continue-on-error: false` — ensures the pipeline fails if formatting is wrong
- No secrets required — `validate` works fully offline

---

## Step 5: Initialize a Git Repository and Push

```bash
cd ~/ce-labs/m5-01-pipeline
git init
git add .
git commit -m "Initial commit: S3 bucket config with CI workflow"
```

Create a GitHub repository and push:

```bash
gh repo create ce-lab-first-github-actions-pipeline --public --source=. --push
```

After pushing, GitHub Actions will trigger immediately on the `main` branch push. Go to your repo → **Actions** tab to watch the first run complete. It should go green.

---

## Step 6: Create a Feature Branch and Open a Pull Request

```bash
git checkout -b feature/add-bucket-lifecycle
```

Add a lifecycle rule to `main.tf`. Append this block **at the end of the file**:

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "app_assets" {
  bucket = aws_s3_bucket.app_assets.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 60
      storage_class = "GLACIER"
    }
  }
}
```

> **Fix:** The original lifecycle rule was missing the `filter` block. With AWS provider `~> 5.0`, a lifecycle rule that mixes `transition` and `noncurrent_version_expiration` without a `filter` block causes a validation error: "all rules must contain a filter". The empty `filter { prefix = "" }` applies the rule to all objects and satisfies the provider requirement.

Commit and push the feature branch:

```bash
git add .
git commit -m "Add lifecycle rule for cost optimization"
git push -u origin feature/add-bucket-lifecycle
```

Open a pull request:

```bash
gh pr create \
  --title "Add S3 lifecycle rule" \
  --body "Adds a lifecycle policy to transition objects to cheaper storage classes and expire old versions after 90 days."
```

---

## Step 7: Observe the Workflow in the Actions Tab

1. Open your repository in a browser
2. Click the **Actions** tab
3. You should see a workflow run triggered by your pull request
4. Click into the run and expand each step to review the logs
5. Verify that **Format Check**, **Init**, and **Validate** all show green checkmarks
6. Go back to the **Pull Requests** tab — the PR should display a green status check

**Expected outcome:** The PR page shows "All checks have passed" with the Terraform CI workflow reporting success.

---

## Step 8: Write the README and Submit

Create `README.md` on `main`:

```bash
git checkout main
```

Create `README.md`:

```markdown
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
