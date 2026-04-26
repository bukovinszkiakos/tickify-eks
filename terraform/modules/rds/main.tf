resource "aws_security_group" "rds" {
  name   = "${var.name}-rds-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    security_groups = [aws_security_group.db_access.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.name}-rds-sg"
    Project     = var.name
    Owner       = var.owner
    Environment = var.environment
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnet-group"
  subnet_ids = var.subnet_ids   

  tags = {
    Name        = "${var.name}-db-subnet-group"
    Project     = var.name
    Owner       = var.owner
    Environment = var.environment
  }
}

resource "aws_db_instance" "this" {
  identifier = "${var.name}-db"

  engine         = "sqlserver-ex"
  instance_class = "db.t3.micro"

  multi_az =  true

  username = var.db_username
  password = var.db_password

  license_model = "license-included"

  allocated_storage       = 20
  backup_retention_period = 7
  skip_final_snapshot     = true

  publicly_accessible = false

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.this.name

  tags = {
    Name        = "${var.name}-db"
    Project     = var.name
    Owner       = var.owner
    Environment = var.environment
  }
}


resource "aws_security_group" "db_access" {
  name   = "${var.name}-db-access-sg"
  vpc_id = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.name}-db-access"
    Project     = var.name
    Owner       = var.owner
    Environment = var.environment
  }
}