# Lab 6 Handoff (state at the end of Lab 5)

Written 2026-11-13, right after Lab 5 was submitted (tag `lab5-submit`). It records
what is still in AWS, how to rebuild, and the traps already hit, so Lab 6 does not
rediscover them.

## What is in AWS right now

**Deleted (nothing billable is left):** the Lab 5 endpoint, configs, models, scaling
target and rollback alarm (`docs/lab_5/lab5-teardown-output.txt`, 6/6 OK), and the whole Lab 2
stack: VPC, NAT gateway, IAM roles, Glue, Feature Store group, SageMaker domain.

**Kept on purpose:**

| Resource | Why |
|---|---|
| Data bucket `northstar-dev-data-<account>` | Detached from Terraform state so the Lab 2 data survives; `features/customers/` dates from 2026-10-30 |
| `datacapture/northstar-churn-prod/` in that bucket | ~300 captured requests from 2026-11-13, both variants, t2.medium and m5.large. **Expires 7 days after capture and is permanently deleted a day later, so it is gone by about 2026-11-21.** Lab 6 will probably need a fresh deployment to have data |
| Terraform state bucket + `northstar-tfstate-lock` table | Remote state |
| Model registry `northstar-churn-models` | v5 and v6 **Approved** (identical weights); v3/v4 Rejected; v1/v2 Pending, and their artifacts are deleted from S3, so they **cannot be deployed** |
| Pipeline `northstar-churn-pipeline`, MLflow app | Lab 3/4 metadata, no meaningful cost |

The Lab 4 CI stack (`northstar-cicd`) does not exist, so pushing to `main` starts no builds.

## Quotas (us-east-1)

| Quota | Value |
|---|---|
| ml.m5.large endpoint (L-614B09FD) | 30 |
| ml.m5.large transform job (L-236AE59F) | 8 |
| ml.m5.large spot training (L-29688C85) | 10 |
| ml.t2.medium endpoint | 2 (default) |

Neither path is quota-blocked. Lab 5 took the real-time path without checking the
transform quota; `docs/lab_5/lab5-deployment-plan.md` section 1 explains why batch with a
Feature Store online lookup was the better architecture.

## Rebuild steps

1. Log in: `aws login` (the session lasts ~15 min). For Terraform, use the self-refreshing
   profile: `export AWS_PROFILE=tf` (PowerShell: `$env:AWS_PROFILE = "tf"` on its own line).
2. `bash scripts/data-bucket.sh attach`: import the surviving bucket **before** apply,
   or apply fails with `BucketAlreadyOwnedByYou`.
3. `cd infrastructure/environments/dev && terraform plan -out=tfplan`, review, then
   `terraform apply tfplan`. Expect about 30 to add and 2 to change (`force_destroy` and the
   lifecycle rule), 0 to destroy.
4. **Never interrupt an apply.** In Lab 5 an interrupted apply created the SageMaker
   domain and a NAT gateway without recording them in state. Recovery:
   `terraform force-unlock <id>` (only after confirming no terraform process is running),
   `terraform state rm` the failed resource, then `terraform import` the real one
   (`aws sagemaker list-domains`, `aws ec2 describe-nat-gateways`).
5. Redeploy the endpoint: `deployment/configs/` holds every config, and
   `docs/lab_5/lab5-deployment-plan.md` has the commands. Models must be recreated first:
   `aws sagemaker create-model --model-name northstar-churn-v5 --primary-container ModelPackageName=<pkg-arn>/5 --execution-role-arn <MLEngineer-arn>`.
6. Teardown: `bash scripts/teardown-lab5.sh`, then `bash scripts/teardown-lab2.sh`
   (that one detaches the data bucket first; wait 15 min after any Glue job).

## Known gaps to fix in Lab 6

- **`northstar-dev-ModelMonitor` cannot read `datacapture/`.** Its policy grants only
  `artifacts/*` read. Add `s3:GetObject` on `datacapture/*` (and `ListBucket`) before any
  monitoring job reads captured data.
- The bucket is SSE-S3 everywhere; the Lab 5 security assessment names SSE-KMS as the
  required standard for personal-data prefixes (remediation, not yet done).
- Model approval and deployment both run under the account admin; no Approver or Deployer
  role exists (STRIDE row 4 in `docs/lab_5/lab5-security-assessment.md`).

## Windows / tooling traps

- `aws.exe` ends `--output text` lines with `\r`. In bash scripts, wrap it:
  `aws () { command aws "$@" | tr -d '\r'; }` (already in both teardown scripts).
- Git's `autocrlf` gives `deployment/configs/sample.csv` CRLF on checkout. Strip it
  (`tr -d '\r'`) before invoking the endpoint, or the XGBoost CSV parser may reject it.
- boto3 under `AWS_PROFILE=tf` costs ~3 s per call (the credentials are refreshed every call).
  Use `AWS_PROFILE=default` for boto3 loops (`botocore[crt]` is in `.venv`); keep `tf`
  for Terraform.
- In PowerShell, plain `bash` launches WSL, not Git Bash. Use
  `& "C:\Program Files\Git\bin\bash.exe"`.
- PowerShell 5.1 `Tee-Object` writes UTF-16 (GitHub shows it as binary); `Out-File`
  and `Set-Content -Encoding utf8` add a BOM that the AWS CLI rejects in
  `--cli-input-json` files. Create JSON files in the editor.
- `ModelLatency` is in microseconds: 200 ms = 200000. The measured baseline on
  ml.m5.large is 4,631 µs.
