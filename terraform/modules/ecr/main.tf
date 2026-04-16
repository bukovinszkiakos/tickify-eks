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