# Cloud TP Finale — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provisionner une infrastructure AWS (2 buckets S3 + Lambda Python 3.11 image→PDF) avec Terraform (modules réutilisables), Ansible (mise à jour du handler), et un pipeline GitHub Actions complet, le tout reproductible via un devShell Nix.

**Architecture:** Le module `s3_bucket` est instancié deux fois (source + destination). Le module `lambda_function` déclare la Lambda, son IAM role, le layer Pillow, le trigger S3 et la permission d'invocation. Ansible zippe et pousse `handler.py` indépendamment de Terraform. GitHub Actions orchestre lint (gitleaks + commitlint en parallèle), Terraform et Ansible en jobs séparés avec filtrage de chemins.

**Tech Stack:** Terraform ≥ 1.6, Python 3.11, Pillow, Ansible + amazon.aws collection, GitHub Actions, Nix + git-hooks.nix (cachix/git-hooks.nix)

## Global Constraints

- Toutes les ressources Terraform portent le tag `Project = "ynov-iac-2025"` via `default_tags` dans le provider — toute ressource non taguée est refusée par la policy IAM
- Région AWS : `eu-west-3`
- Role ARN : `arn:aws:iam::738563260931:role/role_etudiants`
- Runtime Lambda : `python3.11` / architecture `x86_64`
- Terraform version plancher : `>= 1.6`
- Les credentials AWS (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) ne sont **jamais** commités — GitHub Secrets uniquement
- Convention de commits : Conventional Commits avec scopes obligatoires parmi `terraform`, `lambda`, `ansible`, `ci`, `nix`, `docs`

---

## File Map

```
cloud_tp_finale/
├── flake.nix
├── flake.lock                          (généré par nix flake update)
├── .commitlintrc.json
├── .gitignore
│
├── terraform/
│   ├── providers.tf
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── s3_bucket/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── lambda_function/
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
│
├── lambda/
│   ├── handler.py
│   ├── test_handler.py
│   └── layers/
│       └── pillow.zip                  (buildé en Task 4)
│
├── ansible/
│   ├── playbook.yml
│   ├── inventory.ini
│   ├── requirements.yml
│   └── roles/
│       └── update_lambda/
│           ├── defaults/main.yml
│           └── tasks/main.yml
│
└── .github/
    └── workflows/
        └── terraform.yaml
```

---

## Task 1 : Repository + flake.nix + devShell

**Files:**
- Create: `flake.nix`
- Create: `.commitlintrc.json`
- Create: `.gitignore`

**Interfaces:**
- Produces: `nix develop` shell avec tous les outils disponibles + hooks pre-commit installés automatiquement

- [ ] **Step 1 : Initialiser le dépôt git**

```bash
cd /home/spnx/ghq/gitlab.arpanode.fr/ynov/spnx/cloud_tp_finale
git init
```

Expected: `Initialized empty Git repository in .../cloud_tp_finale/.git/`

- [ ] **Step 2 : Créer `.gitignore`**

```gitignore
# Terraform
**/.terraform/
*.tfstate
*.tfstate.backup
*.tfplan
.terraform.lock.hcl
terraform/.terraform.lock.hcl

# Secrets
*.tfvars
!*.tfvars.example

# Python
__pycache__/
*.pyc
.pytest_cache/

# Ansible
*.retry

# Lambda build artifacts
lambda/layers/python/
/tmp/handler.zip

# Nix
.direnv/
result
```

- [ ] **Step 3 : Créer `.commitlintrc.json`**

```json
{
  "extends": ["@commitlint/config-conventional"],
  "rules": {
    "scope-enum": [2, "always", ["terraform", "lambda", "ansible", "ci", "nix", "docs"]],
    "scope-empty": [2, "never"]
  }
}
```

- [ ] **Step 4 : Créer `flake.nix`**

```nix
{
  description = "Cloud TP Finale — IaC AWS (Terraform + Ansible)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, git-hooks }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      checks.${system}.pre-commit-check = git-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          gitleaks.enable = true;
          terraform-format.enable = true;
          commitlint = {
            enable = true;
            name = "commitlint";
            stages = [ "commit-msg" ];
            entry = "${pkgs.nodePackages."@commitlint/cli"}/bin/commitlint --edit";
            language = "system";
            pass_filenames = false;
          };
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        inherit (self.checks.${system}.pre-commit-check) shellHook;
        packages = with pkgs; [
          terraform
          awscli2
          ansible
          python311
          python311Packages.pillow
          python311Packages.boto3
          python311Packages.pytest
          checkov
          infracost
          nodejs_20
          nodePackages."@commitlint/cli"
          nodePackages."@commitlint/config-conventional"
          zip
          unzip
        ];
      };
    };
}
```

- [ ] **Step 5 : Générer le lock file et entrer dans le shell**

```bash
nix flake update
nix develop
```

Expected: le shell s'ouvre, `terraform version` et `aws --version` répondent.

- [ ] **Step 6 : Installer les hooks pre-commit**

(Le `shellHook` de git-hooks.nix installe automatiquement les hooks dans `.git/hooks/` à l'entrée dans `nix develop`. Vérifier :)

```bash
ls .git/hooks/pre-commit .git/hooks/commit-msg
```

Expected: les deux fichiers existent.

- [ ] **Step 7 : Commit initial**

```bash
git add flake.nix flake.lock .commitlintrc.json .gitignore
git commit -m "nix(nix): init devShell with tools and git hooks"
```

---

## Task 2 : GitHub Actions workflow

**Files:**
- Create: `.github/workflows/terraform.yaml`

**Interfaces:**
- Consumes: secrets GitHub `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `INFRACOST_API_KEY`
- Produces: pipeline CI/CD avec 5 jobs : `changes`, `gitleaks`, `commitlint`, `terraform`, `ansible`

- [ ] **Step 1 : Créer le répertoire**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2 : Créer `.github/workflows/terraform.yaml`**

```yaml
name: CI/CD

on:
  push:
    branches: ["**"]
  pull_request:
    branches: ["**"]

jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
      terraform: ${{ steps.filter.outputs.terraform }}
      lambda: ${{ steps.filter.outputs.lambda }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            terraform:
              - 'terraform/**'
            lambda:
              - 'lambda/handler.py'

  gitleaks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  commitlint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: wagoid/commitlint-github-action@v6
        with:
          configFile: .commitlintrc.json

  terraform:
    runs-on: ubuntu-latest
    needs: [changes, gitleaks, commitlint]
    if: needs.changes.outputs.terraform == 'true'
    defaults:
      run:
        working-directory: terraform
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: eu-west-3
          role-to-assume: arn:aws:iam::738563260931:role/role_etudiants
          role-session-name: github-actions-terraform

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~> 1.6"

      - name: fmt
        run: terraform fmt -check -recursive

      - name: init
        run: terraform init

      - name: validate
        run: terraform validate

      - name: plan
        run: terraform plan -out=tfplan

      - name: checkov
        uses: bridgecrewio/checkov-action@v12
        with:
          directory: terraform
          quiet: true
          soft_fail: true

      - name: setup infracost
        uses: infracost/actions/setup@v3
        with:
          api-key: ${{ secrets.INFRACOST_API_KEY }}

      - name: infracost breakdown
        run: infracost breakdown --path .

      - name: apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -auto-approve tfplan

  ansible:
    runs-on: ubuntu-latest
    needs: [changes, gitleaks, commitlint]
    if: needs.changes.outputs.lambda == 'true'
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: eu-west-3
          role-to-assume: arn:aws:iam::738563260931:role/role_etudiants
          role-session-name: github-actions-ansible

      - name: install ansible + collection
        run: |
          pip install ansible ansible-lint
          ansible-galaxy collection install -r ansible/requirements.yml

      - name: ansible-lint
        run: ansible-lint ansible/playbook.yml

      - name: deploy
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: ansible-playbook ansible/playbook.yml -i ansible/inventory.ini
```

- [ ] **Step 3 : Vérifier la syntaxe YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/terraform.yaml'))" && echo "OK"
```

Expected: `OK`

- [ ] **Step 4 : Commit**

```bash
git add .github/workflows/terraform.yaml
git commit -m "ci(github-actions): add lint, terraform, and ansible jobs"
```

---

## Task 3 : Module Terraform `s3_bucket`

**Files:**
- Create: `terraform/modules/s3_bucket/variables.tf`
- Create: `terraform/modules/s3_bucket/main.tf`
- Create: `terraform/modules/s3_bucket/outputs.tf`

**Interfaces:**
- Consumes: rien
- Produces: `module.bucket_source.bucket_id`, `module.bucket_source.bucket_arn` (idem pour `bucket_dest`)

- [ ] **Step 1 : Créer `terraform/modules/s3_bucket/variables.tf`**

```hcl
variable "bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name"
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

- [ ] **Step 2 : Créer `terraform/modules/s3_bucket/main.tf`**

```hcl
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

- [ ] **Step 3 : Créer `terraform/modules/s3_bucket/outputs.tf`**

```hcl
output "bucket_id" {
  value = aws_s3_bucket.this.id
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}
```

- [ ] **Step 4 : Commit**

```bash
git add terraform/modules/s3_bucket/
git commit -m "feat(terraform): add reusable s3_bucket module"
```

---

## Task 4 : Lambda handler + Pillow layer + test unitaire

**Files:**
- Create: `lambda/handler.py`
- Create: `lambda/test_handler.py`
- Create: `lambda/layers/pillow.zip` (build avec pip)

**Interfaces:**
- Consumes: variable d'env `DEST_BUCKET` injectée par Terraform
- Produces: `handler.lambda_handler(event, context)` — convertit l'image S3 en PDF et l'uploade dans le bucket destination

- [ ] **Step 1 : Créer `lambda/handler.py`**

```python
import boto3
import os
from PIL import Image
from io import BytesIO
from pathlib import Path

s3 = boto3.client("s3")
DEST_BUCKET = os.environ["DEST_BUCKET"]


def lambda_handler(event, context):
    record = event["Records"][0]
    src_bucket = record["s3"]["bucket"]["name"]
    src_key = record["s3"]["object"]["key"]

    obj = s3.get_object(Bucket=src_bucket, Key=src_key)
    img = Image.open(BytesIO(obj["Body"].read())).convert("RGB")

    pdf_key = str(Path(src_key).with_suffix(".pdf"))
    buf = BytesIO()
    img.save(buf, format="PDF")
    buf.seek(0)

    s3.put_object(
        Bucket=DEST_BUCKET,
        Key=pdf_key,
        Body=buf,
        ContentType="application/pdf",
    )
```

- [ ] **Step 2 : Créer `lambda/test_handler.py`**

```python
import os
from io import BytesIO
from unittest.mock import MagicMock, patch

import pytest

os.environ["DEST_BUCKET"] = "test-dest-bucket"


def _make_image(fmt="JPEG"):
    from PIL import Image
    img = Image.new("RGB", (10, 10), color="red")
    buf = BytesIO()
    img.save(buf, format=fmt)
    return buf.getvalue()


def _event(bucket, key):
    return {"Records": [{"s3": {"bucket": {"name": bucket}, "object": {"key": key}}}]}


@patch("handler.s3")
def test_jpeg_converted_to_pdf(mock_s3):
    mock_s3.get_object.return_value = {"Body": MagicMock(read=lambda: _make_image("JPEG"))}

    from handler import lambda_handler
    lambda_handler(_event("src-bucket", "photo.jpg"), None)

    mock_s3.put_object.assert_called_once()
    kwargs = mock_s3.put_object.call_args.kwargs
    assert kwargs["Bucket"] == "test-dest-bucket"
    assert kwargs["Key"] == "photo.pdf"
    assert kwargs["ContentType"] == "application/pdf"


@patch("handler.s3")
def test_png_rgba_converted_to_pdf(mock_s3):
    from PIL import Image
    img = Image.new("RGBA", (10, 10), color=(255, 0, 0, 128))
    buf = BytesIO()
    img.save(buf, format="PNG")
    mock_s3.get_object.return_value = {"Body": MagicMock(read=lambda: buf.getvalue())}

    from handler import lambda_handler
    lambda_handler(_event("src-bucket", "image.png"), None)

    kwargs = mock_s3.put_object.call_args.kwargs
    assert kwargs["Key"] == "image.pdf"


@patch("handler.s3")
def test_output_key_strips_extension(mock_s3):
    mock_s3.get_object.return_value = {"Body": MagicMock(read=lambda: _make_image())}

    from handler import lambda_handler
    lambda_handler(_event("src-bucket", "folder/shot.jpeg"), None)

    kwargs = mock_s3.put_object.call_args.kwargs
    assert kwargs["Key"] == "folder/shot.pdf"
```

- [ ] **Step 3 : Lancer les tests (doivent passer)**

```bash
cd lambda && python -m pytest test_handler.py -v
```

Expected :
```
test_handler.py::test_jpeg_converted_to_pdf PASSED
test_handler.py::test_png_rgba_converted_to_pdf PASSED
test_handler.py::test_output_key_strips_extension PASSED
3 passed
```

- [ ] **Step 4 : Builder le layer Pillow pour Lambda Linux x86_64**

```bash
mkdir -p lambda/layers
pip install \
  --target lambda/layers/python \
  --platform manylinux2014_x86_64 \
  --implementation cp \
  --python-version 3.11 \
  --only-binary=:all: \
  pillow
cd lambda/layers && zip -r pillow.zip python/ && rm -rf python/
cd ../..
```

Expected: `lambda/layers/pillow.zip` créé (~8 MB).

```bash
ls -lh lambda/layers/pillow.zip
```

- [ ] **Step 5 : Commit**

```bash
git add lambda/handler.py lambda/test_handler.py lambda/layers/pillow.zip
git commit -m "feat(lambda): add image-to-pdf handler with Pillow layer"
```

---

## Task 5 : Module Terraform `lambda_function` + configuration racine

**Files:**
- Create: `terraform/modules/lambda_function/variables.tf`
- Create: `terraform/modules/lambda_function/main.tf`
- Create: `terraform/modules/lambda_function/outputs.tf`
- Create: `terraform/providers.tf`
- Create: `terraform/main.tf`
- Create: `terraform/variables.tf`
- Create: `terraform/outputs.tf`
- Create: `terraform/terraform.tfvars.example`

**Interfaces:**
- Consumes: `module.bucket_source.bucket_id`, `module.bucket_source.bucket_arn`, `module.bucket_dest.bucket_id`, `module.bucket_dest.bucket_arn`
- Produces: Lambda déployée, trigger S3 configuré, IAM role avec droits S3 minimum

- [ ] **Step 1 : Créer `terraform/modules/lambda_function/variables.tf`**

```hcl
variable "function_name" {
  type = string
}

variable "source_bucket_id" {
  type = string
}

variable "source_bucket_arn" {
  type = string
}

variable "destination_bucket_id" {
  type = string
}

variable "destination_bucket_arn" {
  type = string
}

variable "pillow_layer_path" {
  type    = string
  default = "../lambda/layers/pillow.zip"
}

variable "handler_source_dir" {
  type    = string
  default = "../lambda"
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

- [ ] **Step 2 : Créer `terraform/modules/lambda_function/main.tf`**

```hcl
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "s3_access" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${var.source_bucket_arn}/*"]
  }
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${var.destination_bucket_arn}/*"]
  }
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role_policy" "s3_access" {
  name   = "${var.function_name}-s3"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.s3_access.json
}

resource "aws_lambda_layer_version" "pillow" {
  filename                 = var.pillow_layer_path
  layer_name               = "${var.function_name}-pillow"
  compatible_runtimes      = ["python3.11"]
  compatible_architectures = ["x86_64"]
  source_code_hash         = filebase64sha256(var.pillow_layer_path)
}

data "archive_file" "handler" {
  type        = "zip"
  source_file = "${var.handler_source_dir}/handler.py"
  output_path = "${path.module}/handler.zip"
}

resource "aws_lambda_function" "this" {
  filename         = data.archive_file.handler.output_path
  function_name    = var.function_name
  role             = aws_iam_role.lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.handler.output_base64sha256
  layers           = [aws_lambda_layer_version.pillow.arn]
  tags             = var.tags

  environment {
    variables = {
      DEST_BUCKET = var.destination_bucket_id
    }
  }
}

resource "aws_lambda_permission" "s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.source_bucket_arn
}

resource "aws_s3_bucket_notification" "source" {
  bucket = var.source_bucket_id

  lambda_function {
    lambda_function_arn = aws_lambda_function.this.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3]
}
```

- [ ] **Step 3 : Créer `terraform/modules/lambda_function/outputs.tf`**

```hcl
output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "function_arn" {
  value = aws_lambda_function.this.arn
}
```

- [ ] **Step 4 : Créer `terraform/providers.tf`**

```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn     = var.role_arn
    session_name = "terraform-session"
  }

  default_tags {
    tags = {
      Project = "ynov-iac-2025"
    }
  }
}
```

- [ ] **Step 5 : Créer `terraform/variables.tf`**

```hcl
variable "aws_region" {
  type    = string
  default = "eu-west-3"
}

variable "role_arn" {
  type    = string
  default = "arn:aws:iam::738563260931:role/role_etudiants"
}

variable "project_prefix" {
  type    = string
  default = "ynov"
}
```

- [ ] **Step 6 : Créer `terraform/main.tf`**

```hcl
data "aws_caller_identity" "current" {}

locals {
  prefix = var.project_prefix
}

module "bucket_source" {
  source      = "./modules/s3_bucket"
  bucket_name = "${local.prefix}-source-${data.aws_caller_identity.current.account_id}"
}

module "bucket_dest" {
  source      = "./modules/s3_bucket"
  bucket_name = "${local.prefix}-dest-${data.aws_caller_identity.current.account_id}"
}

module "lambda" {
  source                 = "./modules/lambda_function"
  function_name          = "${local.prefix}-image-converter"
  source_bucket_id       = module.bucket_source.bucket_id
  source_bucket_arn      = module.bucket_source.bucket_arn
  destination_bucket_id  = module.bucket_dest.bucket_id
  destination_bucket_arn = module.bucket_dest.bucket_arn
}
```

- [ ] **Step 7 : Créer `terraform/outputs.tf`**

```hcl
output "source_bucket" {
  value = module.bucket_source.bucket_id
}

output "destination_bucket" {
  value = module.bucket_dest.bucket_id
}

output "lambda_function_name" {
  value = module.lambda.function_name
}
```

- [ ] **Step 8 : Créer `terraform/terraform.tfvars.example`**

```hcl
aws_region     = "eu-west-3"
role_arn       = "arn:aws:iam::738563260931:role/role_etudiants"
project_prefix = "ynov"
```

- [ ] **Step 9 : Valider le Terraform**

Depuis `nix develop` avec les credentials AWS configurés dans l'environnement :

```bash
cd terraform
terraform fmt -recursive
terraform init
terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 10 : Commit**

```bash
git add terraform/
git commit -m "feat(terraform): add lambda_function module and root configuration"
```

---

## Task 6 : Ansible — rôle `update_lambda` + playbook

**Files:**
- Create: `ansible/requirements.yml`
- Create: `ansible/inventory.ini`
- Create: `ansible/roles/update_lambda/defaults/main.yml`
- Create: `ansible/roles/update_lambda/tasks/main.yml`
- Create: `ansible/playbook.yml`

**Interfaces:**
- Consumes: `lambda/handler.py`, variable `lambda_function_name` (nom de la Lambda créée par Terraform)
- Produces: code de la Lambda mis à jour via `amazon.aws.lambda`

- [ ] **Step 1 : Créer `ansible/requirements.yml`**

```yaml
collections:
  - name: amazon.aws
    version: ">=7.0.0"
```

- [ ] **Step 2 : Créer `ansible/inventory.ini`**

```ini
[local]
localhost ansible_connection=local
```

- [ ] **Step 3 : Créer `ansible/roles/update_lambda/defaults/main.yml`**

```yaml
---
lambda_function_name: "ynov-image-converter"
lambda_region: "eu-west-3"
lambda_handler_dir: "{{ playbook_dir }}/../lambda"
```

- [ ] **Step 4 : Créer `ansible/roles/update_lambda/tasks/main.yml`**

```yaml
---
- name: Package handler.py into a zip
  ansible.builtin.shell:
    cmd: "zip /tmp/handler.zip handler.py"
    chdir: "{{ lambda_handler_dir }}"

- name: Update Lambda function code
  amazon.aws.lambda:
    name: "{{ lambda_function_name }}"
    state: present
    zip_file: /tmp/handler.zip
    runtime: python3.11
    handler: handler.lambda_handler
    region: "{{ lambda_region }}"

- name: Remove temporary zip
  ansible.builtin.file:
    path: /tmp/handler.zip
    state: absent
```

- [ ] **Step 5 : Créer `ansible/playbook.yml`**

```yaml
---
- name: Deploy Lambda handler
  hosts: localhost
  connection: local
  gather_facts: false
  roles:
    - update_lambda
```

- [ ] **Step 6 : Installer la collection et lancer ansible-lint**

```bash
ansible-galaxy collection install -r ansible/requirements.yml
ansible-lint ansible/playbook.yml
```

Expected: pas d'erreur critique (warnings éventuels sur le module `shell` sont acceptables).

- [ ] **Step 7 : Commit**

```bash
git add ansible/
git commit -m "feat(ansible): add update_lambda role and playbook"
```

---

## Vérification finale

- [ ] `nix develop` ouvre le shell avec tous les outils
- [ ] `terraform validate` passe dans `terraform/`
- [ ] `python -m pytest lambda/test_handler.py -v` — 3 tests verts
- [ ] `ansible-lint ansible/playbook.yml` passe
- [ ] `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/terraform.yaml'))"` — OK
- [ ] Un faux secret dans un fichier de test déclenche gitleaks au commit
- [ ] Un message de commit sans scope est rejeté par commitlint
