resource "aws_ecr_repository" "this" {
  name = "${var.name}-backend"

  lifecycle {
    prevent_destroy = true   
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "${var.name}-ecr"
    Project     = "tickify"
    Owner       = "akos"
    Environment = "dev"
  }
}

resource "aws_iam_policy" "ecr_access" {
  name = "${var.name}-ecr-policy"

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
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = aws_ecr_repository.this.arn
      }
    ]
  })
}

resource "aws_iam_role" "ecr_role" {
  name = "${var.name}-ecr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_attach" {
  role       = aws_iam_role.ecr_role.name
  policy_arn = aws_iam_policy.ecr_access.arn
}


resource "aws_iam_user" "ecr_user" {
  count = var.on_premise ? 1 : 0

  name = "${var.name}-ecr-user"

  tags = {
    Name        = "${var.name}-ecr-user"
    Project     = var.name
    Owner       = var.owner
    Environment = var.environment
  }
}


resource "aws_iam_user_policy_attachment" "ecr_user_attach" {
  count = var.on_premise ? 1 : 0

  user       = aws_iam_user.ecr_user[0].name
  policy_arn = aws_iam_policy.ecr_access.arn
}


resource "aws_iam_access_key" "ecr_user_key" {
  count = var.on_premise ? 1 : 0

  user = aws_iam_user.ecr_user[0].name
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last N images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = var.max_images
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}