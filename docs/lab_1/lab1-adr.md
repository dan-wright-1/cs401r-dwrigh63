## ADR-001: NorthStar Platform Foundation

### Status
Accepted

### Context

NorthStar Retail loses approximately 18% of its 2.1M active customers every year, which
at $340 of lost lifetime value per churned customer works out to the $128.5M annual
problem the CDO commissioned this platform to address. That number isn't solved by one
model — it's the combined target of three systems: a batch churn-prediction model that
scores every active customer weekly, an LLM/RAG offer-generation system that has to
respond in under two seconds, and an agentic customer service system that has to hold
99.5% uptime during business hours. All three will eventually read and write the same
customer data, and two more roles (DataEngineer, ModelMonitor) join in Lab 2. So the
identity model — who may touch which data — and the storage tier structure have to exist
*before* real customer data starts moving. Retrofitting access control once PII is
already flowing through `raw/` and `processed/` under GDPR (Canadian customers) and CCPA
(California customers) means auditing and re-permissioning live data instead of just
adding an `aws_iam_role` block.

### Decision

The network layer is one VPC (`northstar-dev-vpc`, `10.0.0.0/16`) with a single public
subnet (`northstar-dev-public-1`, `10.0.100.0/24`, `us-east-1a`). SageMaker Studio runs
here, reachable from the internet for what the Studio UI needs (image pulls, package
installs), but the security group allows inbound only from `10.0.0.0/16` — nothing from
the open internet.

Storage is one S3 bucket (`northstar-dev-data-<account-id>`) with four prefixes:
`raw/`, `processed/`, `features/`, `artifacts/`. This mirrors the actual data lifecycle
each of NorthStar's systems depends on: `raw/` is where the nightly POS export and the
Shopify webhook stream land untouched; `processed/` is cleaned, joined data; `features/`
is what a training job actually reads; `artifacts/` is where a trained churn model or a
registered RAG index gets written. One bucket, not four, because S3 bucket names are
globally unique across all of AWS — with a class of students building the same platform,
four buckets each is four chances to collide; one bucket suffixed with the account ID
collides with nobody.

The identity model is one IAM role, `northstar-dev-MLEngineer`, trusted by
`sagemaker.amazonaws.com` — not an IAM user. SageMaker assumes this role via STS for
every training job and every Studio session, so no long-lived access key ever exists for
it. Its policy is deliberately narrow: SageMaker actions needed for training/endpoints/
MLflow, S3 read/write scoped only to `artifacts/*` and `features/*`, CloudWatch Logs
write, and ECR read for pulling training containers. `raw/` and `processed/` are absent
from the policy entirely — not explicitly denied, just never granted, which is the same
effective result under IAM's default-deny model. That split exists because raw and
processed data are where PII lives before it's been feature-engineered; an ML engineer
training a churn model has no legitimate reason to touch it directly, and Lab 2's
DataEngineer role is what will actually own that access.

### Consequences

#### What this makes easy
Lab 2 adds the DataEngineer and ModelMonitor roles without touching the VPC, the bucket,
or any existing resource — both new roles are just new `aws_iam_role` blocks that
reference the same bucket ARN pattern with different prefix scopes. Because the four
prefixes already exist, Lab 2's Glue ETL jobs can be pointed at `s3://.../raw/` on day
one with no data migration.

#### What this makes harder
S3's IAM model requires `s3:ListBucket` to be granted at the bucket level even when the
underlying object actions (`GetObject`/`PutObject`) are prefix-scoped. That means
`northstar-dev-MLEngineer` can list key names anywhere in the bucket — including
`raw/` and `processed/` — even though it can't read or write their contents. It's a real
least-privilege gap (an attacker with this role could see that a file named
`raw/customer_pii_2026.csv` exists, without being able to open it), and closing it
properly would require S3 access points or bucket policies with explicit deny statements,
which is more infrastructure than Lab 1's scope calls for.

This is not hypothetical. The first draft put the bucket-level ARN (needed only for
`ListBucket`) in the *same* `Resource` array as the object actions; IAM's ARN wildcard
matches across `/`, so that one entry silently granted `PutObject` on `raw/` too.
`verify-lab1.sh`'s policy simulation caught it — `s3:PutObject` on `raw/test.csv`
returned `allowed`, not `implicitDeny` — which is why `ListBucket` now sits in its own
statement scoped to the bucket ARN alone.

#### What would cause you to revisit this decision
If the offer-generation system's 2-second SLA turned out to be unreachable from a
public-subnet, internet-routed path to S3, or if NorthStar decided to pursue the
explicitly out-of-scope real-time personalization feature (<50ms latency), the network
model would need to move to VPC endpoints or PrivateLink rather than routing through the
public internet — a meaningfully different design, not a tweak.

### Alternative Considered
Building the SageMaker subnet as private with a NAT Gateway from the start — the
production-appropriate configuration Lab 2 eventually uses — was the real alternative,
rejected on cost and sequencing grounds: a NAT Gateway runs roughly $32–45/month, a
meaningful chunk of a $200 semester credit budget to spend before the platform has done
anything. Lab 2 adds the private subnet once there's an actual reason (DataEngineer
workloads that shouldn't be internet-reachable) to justify it.

### AWS Service Selection
- **Networking isolation model:** A single public subnet inside one VPC, scoped down by
  security group rather than network topology — the right amount of isolation for a
  platform with one role and no NAT budget yet.
- **Storage design:** One S3 bucket with four prefixes instead of four buckets — avoids
  bucket-name collisions across the class and lets one IAM policy scope access by ARN
  pattern instead of by bucket.
- **Identity model:** An IAM role assumed via STS, not an IAM user — no long-lived
  credentials, and a policy that enforces NorthStar's raw/processed-vs-features/artifacts
  access split by omission.
- **ML development environment:** A single SageMaker Studio Domain — the shared
  environment every future ML system in the case (churn model training now, RAG and
  agent work later) will use, keeping one execution-role model consistent platform-wide.
