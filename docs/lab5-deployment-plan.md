# Lab 5 Deployment Plan: NorthStar Churn Model

## Names used in this plan

Run every command in bash from the repo root, with AWS credentials for the account.

```bash
ACCT=$(aws sts get-caller-identity --query Account --output text)
EP=northstar-churn-prod        # endpoint; variants champion (v5) and canary (v6)
CFG=deployment/configs         # every config file below lives here
PKG=arn:aws:sagemaker:us-east-1:$ACCT:model-package/northstar-churn-models
ROLE=arn:aws:iam::$ACCT:role/northstar-dev-MLEngineer
```

| Plan role | Acts through | Responsible for |
|---|---|---|
| ML Lead | account administrator (only identity with `sagemaker:UpdateModelPackage`) | approval; rollback/promote call |
| ML Engineer | admin credentials; endpoint runs as `northstar-dev-MLEngineer` | rollout, rollback, cleanup |
| Data Engineer | `northstar-dev-DataEngineer` | feature freshness |
| Model Monitor | `northstar-dev-ModelMonitor` | watching the rollback alarm |

## 1. Deployment strategy and rationale

**What we did.** The churn model was deployed as a SageMaker real-time endpoint
with a canary rollout: champion and canary variants at 9:1 on one endpoint. We
chose real-time because live traffic splitting and instant rollback were the
more interesting mechanics to learn, and because we assumed the Batch Transform
quota was still at the new-account default of 0. We never checked; the account
had 8. This was a convenience choice, not a fit to NorthStar's requirements.

**What NorthStar needs.** The churn model has one deadline: weekly scores by
Monday 6 AM ET for the retention campaign. Its only live consumer, offer
generation, reads `churn_probability` as one prompt input inside a 2-second
budget that the LLM call dominates. Nothing needs a model running 24/7.

**What we should have built.** A weekly Batch Transform job scores all 2.1M
active customers after the Sunday feature refresh and writes the scores to the
Feature Store online store. The campaign reads the full list; offer generation
does a millisecond key lookup. The rollout is a shadow run: the candidate scores
the same input as the incumbent and is promoted only if the two top-10% lists
overlap by at least 90%. Compute bills only while the job runs.

**When real-time would pay off:** once features stream (clickstream via
Kinesis), so a customer's risk could change mid-visit. That is out of scope today.

## 2. Pre-deployment checklist

All five must be true before the endpoint is created.

1. **Model approved.** The ML Lead checks the candidate against the Lab 4 gates
   (precision@10% >= 0.50, recall@10% >= 0.25, lift CI lower bound > 0), then approves
   it. `northstar-dev-MLEngineer` can register packages but not approve them, so the
   pipeline cannot approve its own output. This rollout: v5 and v6, identical weights,
   AUC 0.776, P@10 0.693, R@10 0.315, lift CI [0.036, 0.076].
   ```bash
   aws sagemaker update-model-package --model-package-arn $PKG/6 --model-approval-status Approved
   ```
2. **Features fresh.** The Data Engineer confirms `features/customers/` was refreshed within 48 hours.
3. **Quota.** `ml.m5.large for endpoint usage` (L-614B09FD) is at least 2.
4. **Infrastructure.** The Lab 2 stack is applied, and `$ROLE` can write to `datacapture/`.
5. **Payload.** `$CFG/sample.csv` holds one header-less row in `FEATURE_COLUMNS` order.

## 3. Rollback criteria

**Trigger:** the canary's p95 `ModelLatency` exceeds **200000 microseconds (200 ms)**
for **3 consecutive 1-minute periods**. CloudWatch reports this metric in
microseconds; the healthy baseline measured on ml.m5.large was 4,631 µs. The alarm
`northstar-churn-rollback-canary-latency` (`$CFG/rollback-alarm.json`) enters ALARM.

**Who decides:** the ML Lead makes the call; the ML Engineer executes it.

```bash
aws cloudwatch put-metric-alarm --cli-input-json file://$CFG/rollback-alarm.json
aws cloudwatch describe-alarms --alarm-names northstar-churn-rollback-canary-latency --query 'MetricAlarms[].StateValue' --output text
bash $CFG/rollback-action.sh   # canary weight -> 0 in ~90 s; the canary still bills until deleted
```

## 4. Monitoring window

**Production: 48 hours. This lab: 60 minutes** (21:08 to 22:08 UTC, 2026-11-13),
compressed to limit endpoint cost.

**Watched:** the rollback alarm state, per-variant smoke tests, the observed
traffic split, and data capture writing to `datacapture/`. **Clean** means the
alarm stayed OK, both variants returned identical scores (0.406), the split
stayed near 9:1 (17 canary / 183 champion over 200 calls), and capture files appeared.

**What 60 minutes cannot catch:** weekday versus weekend traffic, the Monday
campaign burst and whether scale-out actually fires, slow memory leaks, and
score drift, which needs days of captured data (Lab 6). In production we
would also wire the alarm to trigger `rollback-action.sh` automatically.

## 5. Stakeholder notifications

| Role | Deployment start | Promotion | Rollback |
|---|---|---|---|
| ML Lead | approval record, window times | promote decision | alarm page; decides |
| VP of Technology | endpoint name, window, expected cost | new champion version | incident notice and impact |
| VP of Marketing | none (no campaign impact) | model scoring Monday's list | confirmation Monday's list is unaffected |
| Chief Privacy Officer | data capture on, 7-day expiry | none | none |
| Model Monitor | alarm armed, baseline 4,631 µs | new baseline for Lab 6 | alarm history |

## 6. Post-deployment review

Within 3 business days. Attendees: ML Lead, ML Engineer, Model Monitor, VP of
Technology. Output: a review note in `docs/` covering timeline, alarm history,
cost, and changes to this plan.

## 7. Resource cleanup

After the window, delete in this order: scaling policy and target, rollback
alarm, endpoint, endpoint configs, models. Only deleting the endpoint stops billing.

```bash
bash scripts/teardown-lab5.sh                  # writes docs/lab5-teardown-output.txt
grep -c ' OK$' docs/lab5-teardown-output.txt   # must print 6
```

Kept on purpose: model packages (metadata, unbilled) and `datacapture/` for
Lab 6, deleted by a 7-day lifecycle rule.
