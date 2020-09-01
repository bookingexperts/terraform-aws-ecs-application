data "aws_iam_policy_document" "task-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task-role" {
  name               = local.name
  assume_role_policy = data.aws_iam_policy_document.task-assume-role-policy.json
}

resource "aws_iam_role_policy_attachment" "ses" {
  role       = aws_iam_role.task-role.name
  policy_arn = var.ses_iam_policy.arn
}

resource "aws_iam_role_policy_attachment" "s3" {
  role       = aws_iam_role.task-role.name
  policy_arn = aws_iam_policy.s3.arn
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.task-role.name
  policy_arn = aws_iam_policy.cloudwatch.arn
}

resource "aws_iam_policy" "s3" {
  name = "${local.name}-s3-access"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:ListAllMyBuckets"],
            "Resource": ["arn:aws:s3:::*"]
        },
        {
          "Effect": "Allow",
          "Action": ["s3:ListBucket"],
          "Resource": ["arn:aws:s3:::${local.s3.bucket_name}"]
        },
        {
          "Effect": "Allow",
          "Action": [
            "s3:PutObject",
            "s3:GetObject",
            "s3:DeleteObject",
            "s3:PutObjectAcl"
          ],
          "Resource": ["arn:aws:s3:::${local.s3.bucket_name}/*"]
        }
    ]
}
EOF
}

resource "aws_iam_policy" "cloudwatch" {
  name = "${local.name}-cloudwatch-logging-access"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:PutLogEvents",
                "logs:CreateLogGroup",
                "logs:DeleteRetentionPolicy",
                "logs:PutRetentionPolicy"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        }
    ]
}
EOF
}
