# modules/compute/iam.tf
# IAM roles and policies for EC2 instances

###########################
# EC2 Instance IAM Role
###########################

resource "aws_iam_role" "ec2_instance" {
  name = "${var.stack_name}-ec2-instance-role"

  # Permit long AssumeRole sessions so the cache broker can mint credentials
  # that cover a full-length job. The broker requests the actual shorter
  # duration; this only raises the role ceiling.
  max_session_duration = 43200

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Principal = {
            Service = data.aws_service_principal.ec2.name
          }
          Action = "sts:AssumeRole"
        }
      ],
      var.enable_cache_isolation ? [
        {
          # The cache credential broker assumes this role to mint scoped cache
          # sessions. The broker role is created after this role, so use the
          # account root as the trust principal and pin the real caller with
          # aws:PrincipalArn; the tag conditions guarantee every brokered
          # session carries exactly the two session tags the scoped-cache
          # statements key on.
          Effect = "Allow"
          Principal = {
            AWS = "arn:${local.partition}:iam::${var.account_id}:root"
          }
          Action = [
            "sts:AssumeRole",
            "sts:TagSession"
          ]
          Condition = {
            ArnEquals = {
              "aws:PrincipalArn" = "arn:${local.partition}:iam::${var.account_id}:role/${var.stack_name}-cache-broker-role"
            }
            StringEquals = {
              "aws:RequestTag/runs-on-cache-brokered" = "true"
            }
            StringLike = {
              "aws:RequestTag/runs-on-cache-repository" = "*/*"
            }
            "ForAllValues:StringEquals" = {
              "aws:TagKeys" = [
                "runs-on-cache-brokered",
                "runs-on-cache-repository"
              ]
            }
          }
        }
      ] : []
    )
  })

  permissions_boundary = var.permission_boundary_arn != "" ? var.permission_boundary_arn : null

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-ec2-instance-role"
    }
  )
}

# Attach AWS managed policies
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_custom_additional" {
  count = length(var.runner_custom_policy_arns)

  role       = aws_iam_role.ec2_instance.name
  policy_arn = var.runner_custom_policy_arns[count.index]
}

# Inline policies for EC2 instances
resource "aws_iam_role_policy" "ec2_read_only" {
  name = "ReadOnly"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeTags",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      }
    ]
  })
}

# Public ECR hosts common upstream mirrors such as Docker Library images; keep this
# action-scoped and constrain the STS bearer token to ECR Public.
resource "aws_iam_role_policy" "ec2_ecr_public_read_only" {
  name = "EcrPublicReadOnly"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr-public:GetAuthorizationToken",
          "ecr-public:BatchCheckLayerAvailability",
          "ecr-public:GetRepositoryPolicy",
          "ecr-public:DescribeRepositories",
          "ecr-public:DescribeRegistries",
          "ecr-public:DescribeImages",
          "ecr-public:DescribeImageTags",
          "ecr-public:GetRepositoryCatalogData",
          "ecr-public:GetRegistryCatalogData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetServiceBearerToken"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "sts:AWSServiceName" = "ecr-public.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_create_tags" {
  name = "CreateTags"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Deny"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "*"
        Condition = {
          "ForAnyValue:StringEquals" = {
            "aws:TagKeys" = [
              "runs-on-pool-name",
              "runs-on-pool-spec-hash",
              "runs-on-pool-standby-type",
              "runs-on-pool-detached-at",
              "runs-on-pool-lease-state",
            ]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:${local.partition}:ec2:${var.region}:${var.account_id}:instance/*"
        Condition = {
          StringEquals = {
            "aws:ARN" = "$${ec2:SourceInstanceARN}"
          }
        }
      }
    ]
  })
}

# Preserve released singleton state after these legacy sticky-disk grants
# became count-gated by enable_stickydisk_isolation.
moved {
  from = aws_iam_role_policy.ec2_create_tags_volumes
  to   = aws_iam_role_policy.ec2_create_tags_volumes[0]
}

moved {
  from = aws_iam_role_policy.ec2_snapshot_describe
  to   = aws_iam_role_policy.ec2_snapshot_describe[0]
}

moved {
  from = aws_iam_role_policy.ec2_snapshot_create
  to   = aws_iam_role_policy.ec2_snapshot_create[0]
}

moved {
  from = aws_iam_role_policy.ec2_snapshot_lifecycle
  to   = aws_iam_role_policy.ec2_snapshot_lifecycle[0]
}

# Legacy grant for the v1 runs-on/snapshot action (job-side AWS calls).
# Removed when sticky-disk isolation is on: sticky disks tag at creation from
# the control plane, and job-writable tags would allow lineage poisoning.
resource "aws_iam_role_policy" "ec2_create_tags_volumes" {
  count = var.enable_stickydisk_isolation ? 0 : 1

  name = "CreateTagsOnVolumesAndSnapshots"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = [
          "arn:${local.partition}:ec2:${var.region}:${var.account_id}:volume/*",
          "arn:${local.partition}:ec2:${var.region}:*:snapshot/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_cloudwatch_logs" {
  name = "SendLogs"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:${local.partition}:logs:${var.region}:${var.account_id}:log-group:${local.log_group_name}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_cloudwatch_metrics" {
  name = "PutMetrics"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = [
              "RunsOn/Runners",
              "CWAgent"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_get_metrics" {
  name = "GetMetrics"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics"
        ]
        Resource = "*"
      }
    ]
  })
}

locals {
  # Direct cache clients use the instance profile and intentionally share this
  # namespace across every repository attached to the stack. Repository
  # prefixes prevent collisions; they are not an IAM isolation boundary.
  ec2_s3_direct_cache_statements = [
    {
      Effect = "Allow"
      Action = [
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
      ]
      Resource = [
        var.extras.cache.bucket_arn,
      ]
      Condition = {
        StringLike = {
          "s3:prefix" = [
            "cache",
            "cache/*",
          ]
        }
      }
    },
    {
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload",
      ]
      Resource = [
        "${var.extras.cache.bucket_arn}/cache/*"
      ]
    }
  ]
}

resource "aws_iam_role_policy" "ec2_s3_access" {
  name = "EC2AccessS3BucketPolicy"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "s3:GetBucketLocation",
          ]
          Resource = [
            var.extras.cache.bucket_arn,
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "s3:ListBucket",
            "s3:ListBucketMultipartUploads",
          ]
          Resource = [
            var.extras.cache.bucket_arn,
          ]
          Condition = {
            StringLike = {
              "s3:prefix" = [
                "agents",
                "agents/*",
                "runners/$${aws:userid}/",
                "runners/$${aws:userid}/*",
              ]
            }
          }
        },
        {
          Effect = "Allow"
          Action = [
            "s3:PutObject"
          ]
          Resource = [
            "${var.extras.cache.bucket_arn}/cache/metrics/v1/*"
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:DeleteObject"
          ]
          Resource = [
            "${var.extras.cache.bucket_arn}/runners/$${aws:userid}/*"
          ]
        },
        {
          # Volume-scoped sticky-disk clean-unmount markers are the only keys
          # the instance may write under its runners/ prefix. runner-identity.json
          # remains unwritable from the instance.
          Effect = "Allow"
          Action = [
            "s3:PutObject"
          ]
          Resource = [
            "${var.extras.cache.bucket_arn}/runners/$${aws:userid}/stickydisk-clean/*"
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject"
          ]
          Resource = [
            "${var.extras.cache.bucket_arn}/agents/*"
          ]
        }
      ],
      local.ec2_s3_direct_cache_statements
    )
  })
}

# Scoped Magic Cache namespace: only broker-minted sessions (tagged by the
# trust policy and carrying the broker-only STS session-name prefix) may touch
# scoped-cache/*.
# The namespace deliberately lives OUTSIDE cache/, so the direct cache/*
# grants above never reach it and plain instance-profile credentials get an
# implicit deny. Direct clients such as runs-on/cache, sccache, and
# gocacheprog continue using the stack-shared cache/* namespace. The broker's
# per-token session policy then narrows scoped-cache/* access to the job's
# exact repository and scopes.
# Admin-attached runner_custom_policy_arns are still unioned onto this role;
# broad custom S3 policies can intentionally bypass the broker. Use them only
# when direct runner access to stack-owned cache data is acceptable.
resource "aws_iam_role_policy" "ec2_scoped_cache_broker" {
  name = "ScopedCacheBrokerAccess"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads"
        ]
        Resource = var.extras.cache.bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix"  = ["scoped-cache/*"]
            "aws:userid" = "*:runs-on-cache-i-*"
          }
          StringEquals = {
            "aws:PrincipalTag/runs-on-cache-brokered" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = "${var.extras.cache.bucket_arn}/scoped-cache/*"
        Condition = {
          StringLike = {
            "aws:userid" = "*:runs-on-cache-i-*"
          }
          StringEquals = {
            "aws:PrincipalTag/runs-on-cache-brokered" = "true"
          }
        }
      },
      {
        # The agent invokes the broker with its instance-profile session.
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:${local.partition}:lambda:${var.region}:${var.account_id}:function:${var.stack_name}-cache-broker"
      },
      {
        # Brokered sessions must not re-mint themselves through the broker
        # (the caller-identity proof cannot tell a brokered session apart
        # from the instance session). Role-side so it costs no STS
        # packed-policy budget.
        Effect = "Deny"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:${local.partition}:lambda:${var.region}:${var.account_id}:function:${var.stack_name}-cache-broker"
        Condition = {
          StringLike = {
            "aws:userid" = "*:runs-on-cache-i-*"
          }
          StringEquals = {
            "aws:PrincipalTag/runs-on-cache-brokered" = "true"
          }
        }
      }
    ]
  })
}

# Legacy grants for the v1 runs-on/snapshot action (job-side AWS calls).
# Removed when sticky-disk isolation is on: all sticky-disk EBS operations run
# on the control plane, so runners need no volume/snapshot permissions at all.
resource "aws_iam_role_policy" "ec2_snapshot_describe" {
  count = var.enable_stickydisk_isolation ? 0 : 1

  name = "VolumeSnapshotDescribe"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_snapshot_create" {
  count = var.enable_stickydisk_isolation ? 0 : 1

  name = "VolumeSnapshotCreate"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume",
          "ec2:CreateSnapshot"
        ]
        Resource = [
          "arn:${local.partition}:ec2:${var.region}:${var.account_id}:volume/*",
          "arn:${local.partition}:ec2:${var.region}::snapshot/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_snapshot_lifecycle" {
  count = var.enable_stickydisk_isolation ? 0 : 1

  name = "VolumeSnapshotLifecycle"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DeleteVolume",
          "ec2:DeleteSnapshot"
        ]
        Resource = [
          "arn:${local.partition}:ec2:${var.region}:${var.account_id}:volume/*",
          "arn:${local.partition}:ec2:${var.region}::snapshot/*",
          "arn:${local.partition}:ec2:${var.region}:${var.account_id}:instance/*"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/runs-on-stack-name" = var.stack_name
          }
        }
      }
    ]
  })
}

# EFS access policy (conditional)
resource "aws_iam_role_policy" "ec2_efs_access" {
  count = var.extras.efs.enabled ? 1 : 0

  name = "EfsMountAccess"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:DescribeMountTargets"
        ]
        Resource = var.extras.efs.file_system_arn
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeSubnets",
          "ec2:DescribeNetworkInterfaces"
        ]
        Resource = "*"
      }
    ]
  })
}

# ECR access policy (conditional)
resource "aws_iam_role_policy" "ec2_ecr_access" {
  count = var.extras.ecr.enabled ? 1 : 0

  name = "EphemeralRegistryAccess"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = var.extras.ecr.repository_arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_ecr_pull_through_cache_access" {
  count = var.extras.pull_through_cache.enabled ? 1 : 0

  name = "EcrPullThroughCacheAccess"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:CreateRepository",
          "ecr:BatchImportUpstreamImage"
        ]
        # Every rule uses a repository prefix (ROOT is rejected by module
        # validation), so runner access stays scoped to the cache namespaces.
        Resource = distinct([
          for rule in values(var.extras.pull_through_cache.rules) :
          "arn:${local.partition}:ecr:${var.region}:${var.account_id}:repository/${rule.ecr_repository_prefix}/*"
        ])
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_bedrock_access" {
  count = var.enable_bedrock ? 1 : 0

  name = "BedrockAccess"
  role = aws_iam_role.ec2_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ListInferenceProfiles"
        ]
        Resource = [
          "arn:${local.partition}:bedrock:*:*:foundation-model/*",
          "arn:${local.partition}:bedrock:*:*:inference-profile/*",
          "arn:${local.partition}:bedrock:*:*:application-inference-profile/*"
        ]
      }
    ]
  })
}

# EC2 Instance Profile
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.stack_name}-ec2-instance-profile"
  role = aws_iam_role.ec2_instance.name

  tags = merge(
    local.common_tags,
    {
      Name = "${var.stack_name}-ec2-instance-profile"
    }
  )
}
