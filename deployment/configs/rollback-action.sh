#!/usr/bin/env bash
# Rollback: route all traffic to the champion by setting the canary's weight to 0.
# Takes ~90 s; the endpoint shows Updating but keeps serving (no dropped requests).
# NOTE: the canary instance still bills at weight 0. Only deleting the endpoint stops it.
set -euo pipefail
EP=northstar-churn-prod

aws sagemaker update-endpoint-weights-and-capacities \
  --endpoint-name "$EP" \
  --desired-weights-and-capacities VariantName=canary,DesiredWeight=0 VariantName=champion,DesiredWeight=1

aws sagemaker wait endpoint-in-service --endpoint-name "$EP"
aws sagemaker describe-endpoint --endpoint-name "$EP" \
  --query 'ProductionVariants[].[VariantName,CurrentWeight]' --output text
