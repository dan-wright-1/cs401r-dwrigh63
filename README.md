# NorthStar Retail — AI Platform (CS 401R)

Coursework repository for CS 401R. Builds the NorthStar Retail AI platform on AWS
across seven labs; each lab extends the previous one rather than replacing it.

## Layout

```
infrastructure/
  modules/        vpc, storage, iam, sagemaker  — reusable, environment-agnostic
  environments/
    dev/          the real AWS deployment (S3 remote state + DynamoDB lock)
    local/        the same modules against LocalStack (no sagemaker — not emulated)
scripts/
  bootstrap-state.sh   one-time remote-state bucket + lock table setup
  verify-lab1.sh       rubric checks against a live stack
  check-secrets.sh     scans all git history for committed credentials
docs/                  diagrams, screenshots, ADR, cost estimate, run outputs
```

## Usage

```bash
bash scripts/bootstrap-state.sh          # once per account
cd infrastructure/environments/dev
terraform init && terraform plan && terraform apply
bash ../../../scripts/verify-lab1.sh     # from repo root, while the stack is up
terraform destroy                        # don't leave it running
make local-validate                      # LocalStack check, costs nothing
```

## Labs

| Lab | Scope | Tag |
|---|---|---|
| 1 | Platform foundation — VPC, S3, IAM, SageMaker Domain, Terraform IaC | `lab1-submit` |

Never commit credentials. `.tfvars`, `.tfstate`, and `.env` are gitignored; keep it
that way.
