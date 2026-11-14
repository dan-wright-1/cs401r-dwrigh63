# Lab 5 Security, Privacy & Compliance Assessment: NorthStar Churn Model

Scope: the churn model as deployed in Lab 5 (real-time endpoint `northstar-churn-prod`)
and the Lab 1-4 data platform behind it: one S3 bucket (`northstar-dev-data-<account>`,
prefixes `raw/`, `processed/`, `features/`, `artifacts/`, `datacapture/`), the
`northstar-dev-customer-features` Feature Store group, the Model Registry group
`northstar-churn-models`, and the three Lab 2 IAM roles.

The three roles are service execution roles, assumable only by AWS services:

| Role | Runs | S3 scope |
|---|---|---|
| `northstar-dev-MLEngineer` | SageMaker training jobs and the endpoint | `artifacts/*`, `features/*` read/write; `datacapture/*` write only. No `raw/` or `processed/`, no Glue or Athena |
| `northstar-dev-DataEngineer` | Glue jobs, Feature Store ingest | `raw/`, `processed/`, `features/` read/write. No SageMaker training or serving |
| `northstar-dev-ModelMonitor` | Monitoring (Lab 6) | `artifacts/*` read only; CloudWatch metrics and alarms |

---

## Task 3a. STRIDE Threat Model

| # | Threat | STRIDE Category | Likelihood (H/M/L) | Impact (H/M/L) | Mitigation | AWS Control |
|---|---|---|---|---|---|---|
| 1 | Leaked AWS credentials (for example, keys committed to this public repo) are used to call `InvokeEndpoint` or the SageMaker control plane as NorthStar | Spoofing | M | H | No long-lived access keys: humans use short-lived `aws login` sessions; CI scans every commit for secrets; only the offer-generation service identity may invoke the endpoint | **IAM** policy scoping `sagemaker:InvokeEndpoint` to `endpoint/northstar-churn-prod` for one caller role; **STS** short-lived credentials; `scripts/check-secrets.sh` and **CodeBuild** `bandit` step in `buildspec.yml` |
| 2 | An attacker who compromises the endpoint container (or its execution role) tries to read raw customer PII to exfiltrate it | Information Disclosure | L | H | **Blast radius contained by `northstar-dev-MLEngineer`:** the endpoint runs as this role, which has no access to `raw/` or `processed/`, no Glue or Athena, and can only *write* `datacapture/*`. The worst case is exposure of 11-number feature vectors and model artifacts, not names, emails or transactions | **IAM** least-privilege execution role (Lab 2, `S3ArtifactsAndFeatures` + `S3DataCaptureWrite` statements); **S3** prefix-scoped resource ARNs; `iam:PassRole` limited to itself and to `sagemaker.amazonaws.com` (`PassSelfToSageMaker`) |
| 3 | A model artifact (`model.tar.gz` under `artifacts/`) is overwritten after approval, so the endpoint serves a poisoned model that under-scores high-value churners | Tampering | L | H | Deploy only from an Approved Model Registry package, whose `ModelDataUrl` is fixed at registration; versioning keeps the approved bytes recoverable; compare the artifact's checksum at deploy time against the one recorded at registration | **SageMaker Model Registry** approval status; **S3 Versioning** (enabled on the bucket); **S3 Object Lock** (governance mode) on `artifacts/models/` and `artifacts/training/` as the production addition |
| 4 | Whoever approved v5/v6 or shifted endpoint weights cannot be identified afterwards, because every action ran under one administrator login | Repudiation | H | M | **Gap the Lab 2 roles do not close:** none of the three roles can approve a model (none has `sagemaker:UpdateModelPackage`) and none is assumable by a person, so approval and deployment both fall back to a single shared admin identity. CloudTrail records *which identity* acted, not *which human*. Fix: separate human-assumable **Approver** (only `UpdateModelPackage`) and **Deployer** roles federated to named users, so no one can approve their own deployment | **AWS CloudTrail** management events on `UpdateModelPackage` and `UpdateEndpointWeightsAndCapacities`; **IAM Identity Center** permission sets per person; approval reason recorded in the package's `ApprovalDescription` |
| 5 | An authorized caller floods the endpoint (bug or abuse), degrading offer generation's 2-second budget and running up cost | Denial of Service | M | M | Auto-scaling absorbs real load; a hard capacity ceiling caps cost; throttle callers before they reach SageMaker; page on invocation spikes | **Application Auto Scaling** target tracking (1000 invocations/instance, `MaxCapacity` 2); **CloudWatch** alarm on `Invocations` and the canary rollback alarm; **API Gateway** usage-plan throttling in front of the endpoint; **AWS Budgets** alert |
| 6 | An attacker with the endpoint's access repeatedly queries it to infer whether a specific customer was in the training data (membership inference) or to reconstruct the model | Information Disclosure | L | M | The endpoint is private (IAM-authenticated, not internet-facing); it returns only a probability; callers are limited to one service; query volume is monitored per caller | **IAM** `InvokeEndpoint` scoping; **VPC interface endpoint (PrivateLink)** for `sagemaker-runtime` so traffic never leaves the VPC; **CloudWatch** per-variant `Invocations` metrics |
| 7 | The SageMaker Pipeline (running as `northstar-dev-MLEngineer`) registers and then promotes its own model without human review | Elevation of Privilege | L | H | `northstar-dev-MLEngineer` can `CreateModelPackage` but not `UpdateModelPackage`, so pipeline output always lands as `PendingManualApproval`; the CI gate (precision/recall/lift) must pass before registration | **IAM** action-level deny by omission on the execution role; **SageMaker Model Registry** `PendingManualApproval` default; **CodeBuild** quality gate in `buildspec.yml` |

Coverage: Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service and
Elevation of Privilege, all six categories. Row 2 is the Lab 2 role that contains the blast
radius; row 4 is the gap those roles do not close.

---

## Task 3b. Data Classification

**Current state:** every prefix in the bucket uses SSE-S3 (bucket default `AES256`),
and the Feature Store online store uses an AWS-owned key. The table below is the
**required** standard; every asset marked SSE-KMS is a remediation item.

**SSE-S3 vs. SSE-KMS.** Both encrypt at rest with AES-256. SSE-S3 keys are owned and
managed entirely by S3: anyone with `s3:GetObject` can read the data. SSE-KMS uses a
customer-managed key, which adds (1) a second permission check (the KMS key policy) on
top of IAM, (2) a CloudTrail record of every decrypt, and (3) crypto-shredding: disabling
or scheduling deletion of the key makes every object under it unreadable at once. Those
three properties matter for personal data and not for public data, and KMS adds per-request
cost, so the choice follows the tier.

| Asset | Location | Tier | Encryption | Reason for that encryption | IAM access policy | Share with third-party vendor? |
|---|---|---|---|---|---|---|
| Customer PII (hashed email, age band, state, zip, signup date, loyalty tier) | `raw/customers/`, `processed/`, CRM source | **Restricted** | **SSE-KMS** (dedicated CMK) | Directly identifying personal data under GDPR/CCPA; needs key-policy separation, decrypt audit, and crypto-shredding for erasure | `northstar-dev-DataEngineer` only; MLEngineer and ModelMonitor have no access | **No.** Only to processors under a signed DPA, minimized to the fields the service needs |
| Transaction history | `raw/transactions/`, `processed/` | **Confidential** | **SSE-KMS** | Linked to a person by `customer_id`; reveals purchasing behavior and payment method | `northstar-dev-DataEngineer` read/write; MLEngineer sees only derived aggregates in `features/` | **No** at row level; aggregated, de-identified statistics only |
| Behavioral clickstream | `raw/` (streamed via Kinesis) | **Confidential** (Restricted until `search_query` is masked) | **SSE-KMS** | Linked by `customer_id`; `search_query` is known to contain typed email addresses (schema note) | `northstar-dev-DataEngineer`; not ingested by the churn feature pipeline at all | **No** |
| Product catalog | PIM export, `raw/` | **Public** | **SSE-S3** | No personal data, and prices and descriptions are already published on northstar.com; KMS would add cost and decrypt latency for no protection gain | All three roles may read; DataEngineer writes | **Yes** |
| Model weights | `artifacts/training/.../model.tar.gz`, `artifacts/models/` | **Confidential** | **SSE-S3** + versioning and Object Lock | Contains no customer records, so crypto-shredding and decrypt audit add little; the risks are tampering and IP theft, handled by IAM prefix scoping, versioning and Object Lock rather than by the key | `northstar-dev-MLEngineer` read/write; `northstar-dev-ModelMonitor` read only | **No** (proprietary IP; model inversion risk) |
| Inference logs | `datacapture/northstar-churn-prod/` (plus CloudWatch endpoint logs) | **Confidential** | **SSE-KMS** | Each record is one customer's feature vector and churn score: pseudonymous personal data. Kept 7 days, permanently deleted on day 8 (lifecycle rule) | Endpoint writes as `northstar-dev-MLEngineer` (`PutObject` only); ModelMonitor needs a read grant for Lab 6 (not yet in its policy) | **No** |
| Feature Store records | `northstar-dev-customer-features` online store; offline store `features/offline-store/` | **Confidential** | **SSE-KMS** (`KmsKeyId` on both online and offline store configs) | Keyed by `customer_id`: a complete behavioral profile per person, read directly for training | DataEngineer writes (`PutRecord`); MLEngineer reads `features/*` for training | **No** |

---

## Task 4. Privacy Impact Assessment

### Personal data inventory

| Pipeline stage | Where | Personal data processed |
|---|---|---|
| Ingest | `raw/` | `customer_id`, hashed email, age band, state, zip, signup date, loyalty tier and points, lifetime spend; transactions (amount, store, payment method, date); clickstream (session, device, `search_query`) |
| Transform | `processed/` | Cleaned copies of the above, same identifiers |
| Feature engineering | Feature Store online/offline, `features/customers/` | `customer_id` + 13 behavioral features + `churn_label` + `loyalty_tier` per customer |
| Training | SageMaker training job, `artifacts/training/` | Staged copy of the feature table; the trained weights are derived from every customer in it |
| Inference | `northstar-churn-prod` | 11 numeric features per request, **no identifier in the payload**; returns one probability |
| Inference logging | `datacapture/` (7 days) | Request features + returned score, timestamped |
| Use | Retention campaign, offer generation | Top-10% risk list keyed by `customer_id`; `churn_probability` in the offer prompt |

### Lawful basis: legitimate interests (GDPR Art. 6(1)(f))

NorthStar has a legitimate interest in keeping existing customers, and churn prediction
uses purchase history customers already generated with NorthStar, for a purpose they would
reasonably expect from a loyalty-program retailer: being offered a retention discount. The
balancing test favors NorthStar because the processing is low-intrusion. It uses no special-
category data, the model never sees name, email, age or location, and the output only
decides who receives an offer. It produces no legal or similarly significant effect, so
GDPR Art. 22 does not apply.

The other two bases do not fit. **Contractual necessity** fails because predicting churn is
not necessary to fulfil any purchase. **Consent** is workable but wrong: it would have to be
opt-in for all 2.1M customers and withdrawable at any time, and the customers most likely to
churn are the least likely to opt in, which biases the training data against the very
population the model exists to find. Relying on legitimate interests carries an obligation:
customers can object (Art. 21), so an objection flag in the CRM's contact preferences must
exclude them from scoring and outreach.

### Data minimization

Considered and excluded from training:

| Data | Why excluded |
|---|---|
| `age_band`, `state`, `zip_code` | Protected characteristic or a location proxy for one; adds fairness risk with no retention benefit |
| `email` (hashed), `customer_id` | Identifiers, not signal; `customer_id` is used only as the record key |
| `loyalty_tier` | Leaks spend into the model; kept out of the inputs and used only as the fairness slice |
| `churn_risk_score` | A recency heuristic that duplicates `days_since_last_purchase`; it serves as the baseline instead |
| Clickstream, including `search_query` | Not ingested by the feature pipeline at all; `search_query` carries typed email addresses |
| `payment_method`, store-level detail | Financial and location detail not needed to predict churn |

The model uses 11 aggregate behavioral features, and the inference payload carries no
identifier at all.

### Right to erasure workflow: `customer_id = C00123456`

GDPR requires a response within one month. Run in this order, downstream last, so no
later job re-copies the data.

**(a) Raw S3 data.** Files in `raw/` and `processed/` hold many customers each, so the
customer's rows must be filtered out and each affected file rewritten (a Glue job or
Athena `CTAS` with `WHERE customer_id <> 'C00123456'`). The bucket is versioned, so the
rewrite leaves the old file as a noncurrent version, kept 30 days by the lifecycle rule.
Delete those versions explicitly (`aws s3api delete-object --version-id ...`) rather than
waiting. Upstream source systems (CRM, POS, loyalty) need their own deletion request.

**(b) Feature Store.** *Online store:* one call removes the record immediately:
`aws sagemaker-featurestore-runtime delete-record --feature-group-name northstar-dev-customer-features --record-identifier-value-as-string C00123456 --event-time <now> --deletion-mode HardDelete`.
*Offline store:* append-only. The delete only appends a new row with `is_deleted = true`;
every earlier row stays in the Parquet files under `features/offline-store/`. The Lab 3
training query ranks rows and then drops customers whose newest row is a delete marker, so
the customer stops being *used*, but the data is still *stored*. Physically removing it
means rewriting the affected Parquet files without that `customer_id` and deleting the
noncurrent versions (kept 60 days). The same applies to the `features/customers/` export.

**(c) Model training data.** Delete or rewrite the staged copies under `artifacts/training/`.
The trained model is a different problem: its weights were fitted on data that included
this customer, and there is no row to delete. The remedy is to retrain on the cleaned
feature table at the next scheduled run, approve the new version, and then retire and delete
every earlier version (v1 to v6) and its `model.tar.gz`, since all of them were trained on
the customer's data.

**(d) Inference logs.** `datacapture/` records carry no `customer_id`, so they can only be
matched by request time and feature values. Capture expires after 7 days and the
noncurrent version is permanently deleted a day later, so any captured request is gone
within 8 days without manual action, well inside the one-month deadline. CloudWatch
endpoint logs do not contain payloads.

**Hardest step: (c), the trained model.** Erasure there is not a delete operation. The
customer's influence is spread across the split thresholds and leaf values of every tree in
the ensemble, and no API removes one person's contribution. The only reliable remedy is
retraining without them and destroying every model version that saw their data. That costs
a training run and a fresh approval cycle, and it cannot complete until the next retrain,
which is why NorthStar should batch erasure requests into the regular retraining schedule.
The offline Feature Store is the second hardest, for the same reason: its "delete" appends
a marker rather than removing history.
