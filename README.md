# TP Finale — Programmation pour le Cloud

Infrastructure as Code avec **Terraform**, **Ansible** et **AWS**.

Projet fil-rouge Ynov Bordeaux — provisioning d'une chaîne de conversion d'images :
une Lambda est déclenchée à l'upload d'une image dans un bucket S3 source, la convertit
au format PDF, puis dépose le résultat dans un bucket S3 de destination.

---

## Architecture

```
        upload image (.jpg/.png)
                 │
                 ▼
   ┌──────────────────────────┐
   │  S3 — bucket source      │
   │  ynov-source-<account>   │
   └────────────┬─────────────┘
                │ s3:ObjectCreated:*  (notification)
                ▼
   ┌──────────────────────────┐
   │  Lambda                  │      layer Pillow
   │  ynov-image-converter    │◄──── (python3.11)
   │  handler.lambda_handler  │
   └────────────┬─────────────┘
                │ put_object (PDF)
                ▼
   ┌──────────────────────────┐
   │  S3 — bucket destination │
   │  ynov-dest-<account>     │
   └──────────────────────────┘
```

- Le bucket source émet une notification `s3:ObjectCreated:*` qui invoque la Lambda.
- La Lambda lit l'objet, le convertit en PDF avec **Pillow** (fourni via un Lambda layer),
  et écrit `<nom>.pdf` dans le bucket de destination.
- **Ansible** sert ensuite à mettre à jour le code du handler sans repasser par Terraform.

Toutes les ressources portent obligatoirement le tag **`Project = "ynov-iac-2025"`**,
appliqué globalement via `default_tags` du provider AWS (toute ressource non taguée est
refusée par la policy IAM du compte).

---

## Structure du dépôt

```
.
├── terraform/
│   ├── main.tf                  # composition des modules (2 buckets + lambda)
│   ├── providers.tf             # provider AWS (assume role + default_tags), backend TF Cloud
│   ├── variables.tf             # region, role_arn, project_prefix
│   ├── outputs.tf               # noms des buckets + de la lambda
│   ├── terraform.tfvars.example # exemple de variables
│   └── modules/
│       ├── s3_bucket/           # module réutilisable bucket S3 (+ public access block)
│       └── lambda_function/     # module réutilisable Lambda (IAM, layer, notification S3)
├── lambda/
│   ├── handler.py               # code applicatif (conversion image → PDF)
│   ├── test_handler.py          # tests unitaires (pytest)
│   └── layers/pillow.zip        # layer Pillow pré-packagé
├── ansible/
│   ├── playbook.yml             # joue le rôle update_lambda
│   ├── inventory.ini            # localhost (connexion locale)
│   ├── requirements.yml         # collection amazon.aws
│   └── roles/update_lambda/     # zip handler.py + mise à jour du code Lambda
└── .github/workflows/terraform.yaml  # pipeline CI/CD
```

### Modules Terraform

| Module | Rôle | Entrées principales | Sorties |
|---|---|---|---|
| `s3_bucket` | Crée un bucket S3 + public access block | `bucket_name`, `tags` | `bucket_id`, `bucket_arn` |
| `lambda_function` | Crée la Lambda, son rôle/policy IAM, le layer Pillow, la permission et la notification S3 | `function_name`, `source_bucket_*`, `destination_bucket_*` | `function_name`, `function_arn` |

---

## Prérequis

| Outil | Version |
|---|---|
| Terraform CLI | ≥ 1.6 |
| AWS CLI | ≥ 2.x |
| Ansible | avec la collection `amazon.aws` (≥ 7.0.0) |
| Python | 3.11 |

Un compte Terraform Cloud est utilisé comme backend (organisation `Arpanode_Team2`,
workspace `default-prject`). Un token API (`TF_API_TOKEN`) est nécessaire en local
(`terraform login`) ou en CI.

### Authentification AWS (Assume Role)

Le compte AWS est fourni par l'intervenant. Vous recevez une **Access Key / Secret Key**
qui permettent un **Assume Role** vers un rôle IAM restreint.

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=eu-west-3
```

Le provider Terraform (`terraform/providers.tf`) réalise lui-même l'`assume_role` vers
`arn:aws:iam::738563260931:role/role_etudiants`. Vérification manuelle possible :

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::738563260931:role/role_etudiants \
  --role-session-name test-session
```

---

## Déploiement

### 1. Packager les artefacts Lambda

Le module Lambda attend `handler.zip` et `pillow.zip` dans le dossier `terraform/` :

```bash
zip -j terraform/handler.zip lambda/handler.py
cp lambda/layers/pillow.zip terraform/pillow.zip
```

### 2. Provisionner l'infrastructure

```bash
cd terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Variables disponibles (voir `terraform.tfvars.example`) :

| Variable | Défaut | Description |
|---|---|---|
| `aws_region` | `eu-west-3` | Région AWS |
| `role_arn` | `arn:aws:iam::738563260931:role/role_etudiants` | Rôle IAM à assumer |
| `project_prefix` | `ynov` | Préfixe des noms de ressources |

### 3. Tester la chaîne

```bash
# récupérer les noms de buckets
SRC=$(terraform output -raw source_bucket)
DST=$(terraform output -raw destination_bucket)

# uploader une image dans le bucket source
aws s3 cp ./photo.jpg s3://$SRC/photo.jpg

# vérifier le PDF généré dans le bucket destination
aws s3 ls s3://$DST/
aws s3 cp s3://$DST/photo.pdf ./photo.pdf
```

---

## Mise à jour du handler avec Ansible

Pour pousser une nouvelle version du code `handler.py` sans repasser par Terraform :

```bash
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook ansible/playbook.yml -i ansible/inventory.ini
```

Le rôle `update_lambda` zippe `lambda/handler.py` et met à jour le code de la fonction
`ynov-image-converter` via le module `amazon.aws.lambda`. Variables ajustables dans
`ansible/roles/update_lambda/defaults/main.yml` (`lambda_function_name`, `lambda_region`).

---

## Tests

```bash
cd lambda
pip install pillow pytest
pytest
```

Les tests vérifient la conversion JPEG/PNG → PDF et le renommage de la clé de sortie.

---

## CI/CD — GitHub Actions

Pipeline défini dans `.github/workflows/terraform.yaml`, déclenché sur push, pull request
et `workflow_dispatch`.

| Job | Étapes |
|---|---|
| `gitleaks` | Détection de secrets |
| `commitlint` | Vérification des messages de commit |
| `terraform` | packaging Lambda · `fmt` · **Checkov** · `init` · `validate` · `plan` · **Infracost** · `apply` (sur `workflow_dispatch` uniquement) |
| `ansible` | `ansible-lint` · `deploy` (sur `workflow_dispatch` uniquement) |

Les credentials AWS sont assumés via `aws-actions/configure-aws-credentials`.
L'`apply` et le déploiement Ansible ne s'exécutent que sur déclenchement manuel
(`workflow_dispatch`) pour éviter toute modification non intentionnelle.

### Secrets requis

| Secret | Usage |
|---|---|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Authentification AWS |
| `TF_API_TOKEN` | Backend Terraform Cloud |
| `INFRACOST_API_KEY` | Estimation de coûts |

---

## Preuves d'exécution (AWS CLI)

Vérifications réalisées via un **Assume Role** vers `role_etudiants` (profil AWS CLI
configuré avec `role_arn` + `source_profile`), région `eu-west-3`.

### 1. Identité assumée (Assume Role)

```console
$ aws sts get-caller-identity
{
    "UserId": "AROA2X5ONAIBU4G5D353E:botocore-session-1782889815",
    "Account": "738563260931",
    "Arn": "arn:aws:sts::738563260931:assumed-role/role_etudiants/botocore-session-1782889815"
}
```

L'ARN confirme que les commandes s'exécutent bien sous le rôle IAM restreint.

### 2. Buckets S3 provisionnés

```console
$ aws s3 ls | grep ynov-
2026-06-30 14:53:05 ynov-dest-738563260931
2026-06-30 14:53:18 ynov-source-738563260931
```

### 3. Configuration de la Lambda

```console
$ aws lambda get-function-configuration --function-name ynov-image-converter \
    --query '{Name:FunctionName,Runtime:Runtime,Handler:Handler,Timeout:Timeout,Memory:MemorySize,Layers:Layers[].Arn,Env:Environment.Variables}'
{
    "Name": "ynov-image-converter",
    "Runtime": "python3.11",
    "Handler": "handler.lambda_handler",
    "Timeout": 30,
    "Memory": 256,
    "Layers": [
        "arn:aws:lambda:eu-west-3:738563260931:layer:ynov-image-converter-pillow:2"
    ],
    "Env": {
        "DEST_BUCKET": "ynov-dest-738563260931"
    }
}
```

### 4. Déclencheur S3 → Lambda

```console
$ aws s3api get-bucket-notification-configuration --bucket ynov-source-738563260931
{
    "LambdaFunctionConfigurations": [
        {
            "Id": "tf-s3-lambda-20260630125317139000000001",
            "LambdaFunctionArn": "arn:aws:lambda:eu-west-3:738563260931:function:ynov-image-converter",
            "Events": [
                "s3:ObjectCreated:*"
            ]
        }
    ]
}
```

### 5. Test de bout en bout : upload d'une image → PDF renommé

```console
$ aws s3 cp ./facture.png s3://ynov-source-738563260931/facture.png
upload: ./facture.png to s3://ynov-source-738563260931/facture.png

$ aws s3 ls s3://ynov-dest-738563260931/
2026-07-01 09:11:58       5292 facture-20260701-071156.pdf
```

Le fichier a bien été **renommé** (horodatage `AAAAMMJJ-HHMMSS`) **et converti** en PDF.

### 6. Validation du PDF généré

```console
$ aws s3 cp s3://ynov-dest-738563260931/facture-20260701-071156.pdf ./out.pdf
$ file ./out.pdf
./out.pdf: PDF document, version 1.4, 1 page(s)
```

### 7. Trace d'exécution CloudWatch

```console
$ aws logs filter-log-events --log-group-name /aws/lambda/ynov-image-converter \
    --start-time <t> --query 'events[].message' --output text
START RequestId: f2a30c65-3216-4a92-817e-0b255e41b27e Version: $LATEST
END RequestId: f2a30c65-3216-4a92-817e-0b255e41b27e
REPORT RequestId: f2a30c65-3216-4a92-817e-0b255e41b27e Duration: 1891.59 ms \
  Billed Duration: 2449 ms Memory Size: 256 MB Max Memory Used: 111 MB Init Duration: 556.76 ms
```

> **Note :** le timeout de la Lambda a été porté de 3 s (défaut) à **30 s** et la mémoire
> de 128 à **256 MB** (variables `timeout` / `memory_size` du module `lambda_function`).
> Sous 128 MB / 3 s, la conversion Pillow dépassait le timeout (`Status: timeout`) ;
> 256 MB apporte aussi plus de CPU, ramenant la durée à ~1,9 s.

---

## Technologies

| Outil | Rôle |
|---|---|
| Terraform CLI ≥ 1.6 | Provisioning Lambda + S3 (modules réutilisables) |
| AWS CLI v2 | Vérification/interaction S3 & Lambda via Assume Role |
| Ansible (`amazon.aws`) | Mise à jour du code source Lambda |
| GitHub Actions | Pipeline CI/CD |
| Python 3.11 | Runtime Lambda + handler applicatif |
