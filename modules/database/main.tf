variable "vpc_id" {
    type = string
}

variable "private_subnets" {
    type = list(string)
}

variable "app_sg_id" {
    type = string
}

variable "db_username" {
  description = "Database administrator username"
  type        = string
  sensitive   = true
  default     = "admin"
}

variable "db_password" {
  description = "Database administrator password"
  type        = string
  sensitive   = true
  default     = "Admin123"
}

resource "aws_security_group" "db_sg" {
  name        = "wordpress-rds-sg"
  description = "Allow DB access"
  vpc_id      = var.vpc_id

  # Rule 1: From EC2 Security Group
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.app_sg_id]
  }

  # Rule 2: From My IP (Replace 0.0.0.0/0 with your actual IP for security!)
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-rds-sg"
  }
}

resource "aws_db_subnet_group" "default" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = var.private_subnets

  tags = {
    Name = "wordpress-db-subnet-group"
  }
}

resource "aws_db_instance" "default" {
  allocated_storage    = 20
  snapshot_identifier  = "wordpress-backup-kenny"
  instance_class       = "db.t4g.micro"
  engine               = "mysql"
  engine_version       = "8.0"
  
  # Network
  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  availability_zone      = "us-east-1a"
  publicly_accessible    = false
  multi_az               = false # Single-AZ Deployment

  # Config
  identifier             = "wordpress-db"
  username               = var.db_username
  password               = var.db_password
  parameter_group_name   = "default.mysql8.0"
  skip_final_snapshot    = true

  tags = {
    Name = "wordpress-db"
  }
}

resource "aws_secretsmanager_secret" "db_secret" {
  name = "wordpress-mysql"
  description = "Database credentials for WordPress"
  recovery_window_in_days = 0 
}

resource "aws_secretsmanager_secret_version" "db_secret_val" {
  secret_id     = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.default.address
    port     = aws_db_instance.default.port
    dbname   = aws_db_instance.default.db_name
  })
}
