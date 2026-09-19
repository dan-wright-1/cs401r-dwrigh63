# Lab 1 — Monthly Cost Estimate

Steady-state monthly cost for the Lab 1 platform (VPC, S3, IAM, SageMaker Domain,
Terraform remote state), assuming normal dev-cycle usage rather than the one-time
apply/destroy cycles used for grading. Pricing is `us-east-1`, current AWS list pricing.

| Component | Monthly Estimate | Key Assumptions | One Optimization |
|---|---|---|---|
| SageMaker Studio | $2.00 | 1 MLEngineer, ~2 hrs/day × 20 days/month = 40 hrs on `ml.t3.medium` @ $0.05/hr | Attach a Lifecycle Configuration that auto-stops the kernel after 60 min idle. Realistic idle time (forgetting to shut down after a session) is the main driver above the ~15 hrs of actual active use; capping it saves ~$1.25/month (62% of this line). |
| S3 storage | $0.12 | ~5 GB across `raw/`, `processed/`, `features/`, `artifacts/` @ $0.023/GB — modest, since Lab 1 doesn't ingest the full case datasets yet (that's Lab 2) | — |
| Internet Gateway | $0.18 | ~2 GB/month egress from Studio pulling container images and packages @ $0.09/GB (standard data-transfer-out rate after the 100 GB always-free tier) | — |
| DynamoDB (state lock) | $0.00 | On-demand mode; ~50 read/write requests/month from `terraform plan`/`apply` locking — fully covered by the 25 GB storage / 200M requests always-free tier | — |
| S3 state bucket | $0.00 | A handful of `terraform.tfstate` versions, well under 1 MB total — covered by the 5 GB always-free S3 tier | — |
| **Total** | **$2.30** | | |

**Optimization detail:** the SageMaker Studio line is the only one with real room to
shrink, because it's the only resource billed by the hour rather than by usage volume.
Without an auto-stop policy, a kernel left running overnight or over a weekend can
silently rack up 10–20x its intended usage — the $167/month "forgotten endpoint" warning
in `aws-account-setup.md` is the same failure mode at a larger scale. A Lifecycle
Configuration script that calls `SageMaker:StopApp` after a fixed idle window turns that
open-ended risk into a hard ceiling: worst case, one idle kernel running unattended for a
full 30-day month at $0.05/hr is $36, versus $2.00/month for the assumed real usage
pattern — the auto-stop config is what keeps the estimate in this table honest.
