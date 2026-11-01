locals {
  name_prefix = "${var.project}-dev"

  state_bucket_name  = "${local.name_prefix}-files-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  backup_bucket_name = "${local.name_prefix}-backups-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

resource "aws_security_group" "application" {
  name        = "${local.name_prefix}-application"
  description = "Public HTTPS ingress to the Courier application node."
  vpc_id      = aws_vpc.dev.id

  ingress {
    description = "Public HTTPS ingress"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Public HTTP for ACME validation and HTTPS redirect"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound package, image, and AWS API access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-application"
  }
}

resource "aws_eip" "application" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-application-ingress"
  }
}

resource "aws_eip_association" "application" {
  allocation_id = aws_eip.application.id
  instance_id   = aws_instance.application.id
}

resource "aws_security_group" "data" {
  name        = "${local.name_prefix}-data"
  description = "Courier data node; accepts data-plane traffic only from the application node."
  vpc_id      = aws_vpc.dev.id

  egress {
    description = "Outbound package, image, and AWS API access; no inbound internet access is permitted."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-data"
  }
}

resource "aws_vpc_security_group_ingress_rule" "data_from_application" {
  for_each = {
    postgresql = 5432
    redis      = 6379
    kafka      = 9092
    qdrant     = 6333
  }

  security_group_id            = aws_security_group.data.id
  referenced_security_group_id = aws_security_group.application.id
  from_port                    = each.value
  to_port                      = each.value
  ip_protocol                  = "tcp"
  description                  = "${each.key} from the Courier application node"
}

resource "aws_iam_role" "application" {
  name = "${local.name_prefix}-application"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "data" {
  name = "${local.name_prefix}-data"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "application_ssm" {
  role       = aws_iam_role.application.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "application_cloudwatch_agent" {
  role       = aws_iam_role.application.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "data_ssm" {
  role       = aws_iam_role.data.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "data_cloudwatch_agent" {
  role       = aws_iam_role.data.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "application_ecr_and_files" {
  name = "ecr-pull-and-files"
  role = aws_iam_role.application.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuthorization"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPullCourierImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = [for repository in aws_ecr_repository.service : repository.arn]
      },
      {
        Sid      = "CourierFiles"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.files.arn}/*"]
      },
      {
        Sid      = "ListCourierFiles"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.files.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "application_sops_age_key" {
  name = "read-argocd-sops-age-key"
  role = aws_iam_role.application.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadArgoCdSopsAgeKey"
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.sops_age_parameter_name}"
    }]
  })
}

resource "aws_iam_role_policy" "data_backups" {
  name = "backup-bucket"
  role = aws_iam_role.data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CourierBackups"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.backups.arn}/*"]
      },
      {
        Sid      = "ListCourierBackups"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.backups.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "data_runtime_secrets" {
  name = "read-data-runtime-secrets"
  role = aws_iam_role.data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadCourierDataRuntimeSecrets"
      Effect = "Allow"
      Action = ["ssm:GetParameter"]
      Resource = [
        for parameter_name in [
          "postgres-admin-password",
          "courier-app-password",
          "redis-password",
          "qdrant-api-key",
        ] : "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/courier/dev/data/${parameter_name}"
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "application" {
  name = "${local.name_prefix}-application"
  role = aws_iam_role.application.name
}

resource "aws_iam_instance_profile" "data" {
  name = "${local.name_prefix}-data"
  role = aws_iam_role.data.name
}

resource "aws_instance" "data" {
  ami                         = data.aws_ssm_parameter.amazon_linux_arm64.value
  instance_type               = var.data_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.data.id]
  iam_instance_profile        = aws_iam_instance_profile.data.name
  associate_public_ip_address = true
  user_data = templatefile("${path.module}/templates/data-user-data.sh.tftpl", {
    backup_bucket = aws_s3_bucket.backups.bucket
  })
  user_data_replace_on_change = true

  # The AMI lookup intentionally tracks the latest AL2023 release for new
  # environments. Existing stateful dev nodes must not be replaced merely
  # because AWS publishes a newer image; perform a reviewed replacement when
  # scheduling an OS upgrade.
  lifecycle {
    ignore_changes = [ami]
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = var.data_root_volume_size
    tags = {
      Name = "${local.name_prefix}-data-root"
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "${local.name_prefix}-data"
    Role = "data"
  }
}

resource "aws_ebs_volume" "data" {
  availability_zone = aws_instance.data.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "${local.name_prefix}-data-persistent"
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.data.id
}

resource "aws_instance" "application" {
  ami                         = data.aws_ssm_parameter.amazon_linux_arm64.value
  instance_type               = var.application_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.application.id]
  iam_instance_profile        = aws_iam_instance_profile.application.name
  associate_public_ip_address = true
  source_dest_check           = false
  user_data = templatefile("${path.module}/templates/application-user-data.sh.tftpl", {
    data_private_ip                 = aws_instance.data.private_ip
    k3s_version                     = var.k3s_version
    ecr_credential_provider_version = var.ecr_credential_provider_version
  })
  user_data_replace_on_change = true

  # K3s/Argo CD state on this node makes an implicit replacement unsafe. Cloud
  # init user data only runs on first boot, so a later bootstrap change must be
  # applied through a reviewed SSM runbook instead of recreating this node.
  lifecycle {
    ignore_changes = [
      ami,
      user_data,
    ]
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = var.application_root_volume_size
    tags = {
      Name = "${local.name_prefix}-application-root"
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  depends_on = [aws_volume_attachment.data]

  tags = {
    Name = "${local.name_prefix}-application"
    Role = "application"
  }
}
