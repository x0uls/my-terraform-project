variable "vpc_id" {
  type = string
}

variable "public_subnets" {
  type = list(string)
}

variable "private_subnets" {
  type = list(string)
}

resource "aws_security_group" "alb_sg" {
  name        = "wordpress-alb-sg"
  description = "Allow HTTP inbound"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-alb-sg"
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "wordpress-ec2-sg"
  description = "Allow HTTP from ALB"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-ec2-sg"
  }
}

resource "aws_lb" "main" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnets

  tags = {
    Name = "wordpress-alb"
  }
}

resource "aws_lb_target_group" "main" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path = "/"
  }
  
  tags = {
      Name = "wordpress-tg"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
    
  tags = {
    Name = "wordpress-http-listener"
  }
}

resource "aws_launch_template" "wordpress" {
  name_prefix   = "wordpress-lt-"
  image_id      = "ami-043927849594c25e3" # Ubuntu 24.04 LTS (Or user specified)
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y apache2 php libapache2-mod-php php-mysql
              echo "Hello from WordPress Terraform" > /var/www/html/index.html
              systemctl restart apache2
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "wordpress-instance"
    }
  }
    
  tags = {
      Name = "wordpress-lt"
  }
}

resource "aws_autoscaling_group" "bar" {
  name                = "wordpress-asg"
  desired_capacity    = 2
  max_size            = 3
  min_size            = 1
  target_group_arns   = [aws_lb_target_group.main.arn]
  vpc_zone_identifier = var.public_subnets # Placing instances in public subnets for internet access

  launch_template {
    id      = aws_launch_template.wordpress.id
    version = "$Latest"
  }
    
  tag {
    key                 = "Name"
    value               = "wordpress-asg-instance"
    propagate_at_launch = true
  }
}
