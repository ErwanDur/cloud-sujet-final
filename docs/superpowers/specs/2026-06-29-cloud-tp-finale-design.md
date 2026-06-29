# Design — Cloud TP Finale : Infrastructure as Code AWS

**Date :** 2026-06-29
**Projet :** Ynov Bordeaux — Programmation pour le Cloud (AZZOUZ Fadi)
**Stack :** Terraform · Ansible · AWS · GitHub Actions · Nix

---

## Contexte

Projet fil-rouge évalué en soutenance (jour 4). L'objectif est de provisionner une infrastructure AWS composée de deux buckets S3 et d'une Lambda Function via Terraform (modules réutilisables), de gérer les mises à jour du handler Lambda avec Ansible, et d'automatiser le tout dans un pipeline GitHub Actions.

**Contrainte IAM obligatoire :** toutes les ressources Terraform doivent porter le tag `Project = "ynov-iac-2025"` — toute ressource non taguée est refusée par la policy IAM.

---

## Architecture

```
S3 source bucket
    │  (s3:ObjectCreated:* event)
    ▼
Lambda Python 3.11
    │  Pillow : image → PDF (même nom de fichier, extension .pdf)
    ▼
S3 destination bucket

Ansible (job GitHub Actions)
    └─ archive handler.py → amazon.aws.lambda (zip_file) → update function code
```

### Flux de données

1. Une image est uploadée dans le bucket source
2. S3 émet un événement `s3:ObjectCreated:*` → déclenche la Lambda
3. La Lambda télécharge l'objet, le convertit en PDF via Pillow (`.convert("RGB")` pour gérer RGBA/palette), et l'uploade dans le bucket destination avec le même nom + extension `.pdf`
4. Lorsque `lambda/handler.py` est modifié, le job Ansible zippe le handler et appelle `amazon.aws.lambda` avec `zip_file:` pour mettre à jour le code sans retoucher l'infra Terraform

### Formats d'images supportés

Tous les formats supportés par Pillow (JPEG, PNG, GIF, BMP, TIFF, WEBP, etc.) — la Lambda ne filtre pas par content-type, Pillow lève une exception si le fichier n'est pas une image valide (loggée dans CloudWatch).

---

## AWS

| Paramètre | Valeur |
|-----------|--------|
| Région | `eu-west-3` (Paris) |
| Account ID | `738563260931` |
| Role ARN | `arn:aws:iam::738563260931:role/role_etudiants` |
| Auth | Assume Role via Access Key / Secret Key (GitHub Secrets) |

Les credentials ne sont jamais commités — ils sont déclarés comme secrets GitHub Actions : `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`.

---

## Structure du projet

```
cloud_tp_finale/
├── flake.nix                        # devShell + git-hooks.nix
├── flake.lock
├── .commitlintrc.json               # Conventional Commits avec scopes obligatoires
├── .gitignore
│
├── terraform/
│   ├── providers.tf                 # AWS provider + assume_role
│   ├── main.tf                      # instancie les modules
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
│   └── layers/
│       └── pillow.zip               # Pillow pré-compilé Linux x86_64 python3.11
│
├── ansible/
│   ├── playbook.yml
│   ├── inventory.ini
│   ├── requirements.yml             # amazon.aws collection
│   └── roles/
│       └── update_lambda/
│           └── tasks/main.yml
│
└── .github/
    └── workflows/
        └── terraform.yaml
```

**State Terraform :** local (`.tfstate` ignoré par git). Choix adapté à un projet de 4 jours avec IAM restreint.

---

## Modules Terraform

### Module `s3_bucket`

Paramètres : `bucket_name`, `tags`

Ressources :
- `aws_s3_bucket` avec blocage d'accès public activé
- Tag `Project = "ynov-iac-2025"` injecté via variable

Instancié deux fois depuis `main.tf` : une fois pour le bucket source, une fois pour le bucket destination.

### Module `lambda_function`

Paramètres : `function_name`, `handler`, `runtime`, `role_arn`, `source_bucket_arn`, `source_bucket_id`, `destination_bucket`, `layer_arn`, `tags`

Ressources :
- `aws_lambda_function` (runtime `python3.11`, layer Pillow, variable d'env `DEST_BUCKET`)
- `aws_iam_role` + `aws_iam_role_policy` (droits `s3:GetObject` sur bucket source, `s3:PutObject` sur bucket destination)
- `aws_s3_bucket_notification` (trigger `s3:ObjectCreated:*` → Lambda)
- `aws_lambda_permission` (autoriser S3 à invoquer la Lambda)
- `aws_lambda_layer_version` (Pillow pré-compilé pour `python3.11` / `x86_64` — zip buildé via `pip install pillow -t python/` sur Linux x86_64, fourni depuis `lambda/layers/pillow.zip`)

---

## Lambda Handler

```python
# lambda/handler.py
import boto3, os
from PIL import Image
from io import BytesIO
from pathlib import Path

s3 = boto3.client("s3")
DEST_BUCKET = os.environ["DEST_BUCKET"]

def lambda_handler(event, context):
    record = event["Records"][0]
    src_bucket = record["s3"]["bucket"]["name"]
    src_key    = record["s3"]["object"]["key"]

    obj = s3.get_object(Bucket=src_bucket, Key=src_key)
    img = Image.open(BytesIO(obj["Body"].read())).convert("RGB")

    pdf_key = Path(src_key).stem + ".pdf"
    buf = BytesIO()
    img.save(buf, format="PDF")
    buf.seek(0)

    s3.put_object(Bucket=DEST_BUCKET, Key=pdf_key, Body=buf, ContentType="application/pdf")
```

---

## Ansible

Playbook déclenché par le job CI/CD quand `lambda/handler.py` est modifié.

**Rôle `update_lambda`** (`ansible/roles/update_lambda/tasks/main.yml`) :
1. `ansible.builtin.archive` — zippe `lambda/handler.py` vers `/tmp/handler.zip`
2. `amazon.aws.lambda` — appelle `update_function_code` avec `zip_file: /tmp/handler.zip`

Collection requise : `amazon.aws` (installée via `ansible-galaxy collection install amazon.aws`).

Inventory : `localhost` avec connexion locale (`connection: local`) — Ansible n'a pas besoin de SSH, il appelle l'API AWS directement via boto3.

---

## GitHub Actions (`terraform.yaml`)

### Secrets requis

| Secret | Usage |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | Auth AWS |
| `AWS_SECRET_ACCESS_KEY` | Auth AWS |
| `INFRACOST_API_KEY` | Estimation de coût |

### Job `lint` — déclenché sur tout push/PR (en parallèle des autres jobs)

```
gitleaks (scan secrets) ║ commitlint (conventional commits + scopes)
```

Ces deux checks tournent en parallèle et sont indépendants de AWS.

### Job `terraform` — déclenché si `terraform/**` modifié

```
fmt → validate → plan → checkov → infracost → apply (main uniquement)
```

### Job `ansible` — déclenché si `lambda/handler.py` modifié

```
ansible-lint → playbook.yml (zip + update Lambda)
```

Les jobs `terraform` et `ansible` font un `aws sts assume-role` vers `arn:aws:iam::738563260931:role/role_etudiants` avant toute interaction AWS.

---

## Nix (`flake.nix`)

### devShell — outils disponibles dans `nix develop`

| Outil | Version |
|-------|---------|
| `terraform` | ≥ 1.6 |
| `awscli2` | ≥ 2.x |
| `ansible` | avec `amazon.aws` collection |
| `python311` | 3.11 |
| `python311Packages.pillow` | dernière stable |
| `checkov` | dernière stable |
| `infracost` | dernière stable |
| `nodejs` | LTS (pour commitlint) |

### git-hooks.nix — hooks pre-commit

| Hook | Rôle |
|------|------|
| `gitleaks` | Détection de secrets dans les commits |
| `commitlint` | Conventional Commits avec scopes obligatoires |
| `terraform fmt` | Formatage auto des fichiers `.tf` |

### Scopes commitlint valides

`terraform`, `lambda`, `ansible`, `ci`, `nix`, `docs`

Exemples : `feat(terraform): add s3_bucket module`, `fix(lambda): handle RGBA images`, `ci(github-actions): add checkov step`

---

## Ordre d'implémentation

1. `flake.nix` + `.commitlintrc.json` + `.gitignore`
2. `.github/workflows/terraform.yaml`
3. Modules Terraform + `terraform/main.tf`
4. `lambda/handler.py` + layer Pillow
5. Ansible playbook + rôle `update_lambda`
