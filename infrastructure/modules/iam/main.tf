# ── modules/iam ──────────────────────────────────────────────────────────────
# Required resources (Task B1). Exactly one of each:
#
#   aws_iam_role                     MLEngineer, trusted by sagemaker.amazonaws.com
#   aws_iam_policy
#   aws_iam_role_policy_attachment
#
# Least privilege is graded in later labs, so start narrow: grant only the S3
# prefixes and SageMaker actions this role actually needs. A wildcard policy
# here will cost you points in Lab 2.

resource "aws_iam_role" "ml_engineer" {
  name = "${var.project}-${var.environment}-MLEngineer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project}-${var.environment}-MLEngineer"
  }
}

resource "aws_iam_policy" "ml_engineer" {
  name        = "${var.project}-${var.environment}-NorthStarMLEngineerPolicy"
  description = "Least-privilege policy for the MLEngineer SageMaker execution role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SageMakerCore"
        Effect = "Allow"
        Action = [
          "sagemaker:CreateTrainingJob", "sagemaker:DescribeTrainingJob", "sagemaker:StopTrainingJob",
          "sagemaker:CreateEndpoint", "sagemaker:DescribeEndpoint", "sagemaker:DeleteEndpoint",
          "sagemaker:CreateEndpointConfig", "sagemaker:DeleteEndpointConfig",
          "sagemaker:CreateMlflowApp", "sagemaker:DescribeMlflowApp", "sagemaker:ListMlflowApps",
          "sagemaker:CreatePresignedMlflowAppUrl",
          "sagemaker:RegisterModel", "sagemaker:DescribeModelPackage", "sagemaker:ListModelPackages",
        ]
        Resource = "*"
      },
      {
        # ListBucket is a bucket-level action -- it has to target the bare
        # bucket ARN, not an object path. Kept in its own statement on
        # purpose: folding it into S3ArtifactsAndFeatures's Resource list
        # would put "...-data-*" (no path) in an array that also grants
        # GetObject/PutObject/DeleteObject, and IAM's ARN wildcard matches
        # across "/" -- so that single bucket-level entry would silently
        # grant object writes to raw/ and processed/ too.
        Sid      = "S3ListBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::${var.project}-${var.environment}-data-*"
      },
      {
        Sid    = "S3ArtifactsAndFeatures"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [
          "arn:aws:s3:::${var.project}-${var.environment}-data-*/artifacts/*",
          "arn:aws:s3:::${var.project}-${var.environment}-data-*/features/*",
        ]
      },
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:log-group:/aws/sagemaker/*"
      },
      {
        Sid      = "ECRRead"
        Effect   = "Allow"
        Action   = ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:GetAuthorizationToken"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ml_engineer" {
  role       = aws_iam_role.ml_engineer.name
  policy_arn = aws_iam_policy.ml_engineer.arn
}
