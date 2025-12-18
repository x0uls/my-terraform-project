variable "vpc_id" {
    type = string
}

variable "private_subnets" {
    type = list(string)
}

variable "app_sg_id" {
    type = string
}

resource "aws_security_group" "db_sg" {
  name        = "wordpress-db-sg"
  description = "Allow DB access from App"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.app_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-db-sg"
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
  allocated_storage    = 10
  db_name              = "wordpressdb"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  username             = "admin"
  password             = "password123" # In prod, use secrets manager!
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  identifier = "wordpress-db"

  tags = {
    Name = "wordpress-db"
  }
}
