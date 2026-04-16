data "aws_security_groups" "eks_nodes" {
  filter {
    name   = "group-name"
    values = ["*node*"]
  }
}


resource "aws_security_group" "rds" {
  name   = "${var.name}-rds-sg"
  vpc_id = var.vpc_id

  ingress {
  from_port   = 1433
  to_port     = 1433
  protocol    = "tcp"
  cidr_blocks = [var.vpc_cidr]
}

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.name}-rds-sg"
    Project     = "tickify"
    Owner       = "akos"
    Environment = "dev"
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnet-group"
  subnet_ids = var.subnet_ids
}

resource "aws_db_instance" "this" {
  identifier = "${var.name}-db"

  engine         = "sqlserver-ex"   
  instance_class = "db.t3.micro"    

  multi_az = false                 

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
    Project     = "tickify"
    Owner       = "akos"
    Environment = "dev"
  }
}