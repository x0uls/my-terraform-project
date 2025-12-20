variable "vpc_id" {
  type = string
}

variable "public_subnets" {
  type = list(string)
}

variable "private_subnets" {
  type = list(string)
}

variable "db_endpoint" {
  type = string
}

variable "db_secret_arn" {
  type = string
}

data "aws_iam_instance_profile" "lab_profile" {
  name = "LabInstanceProfile"
}

resource "aws_security_group" "ec2_sg" {
  name        = "wordpress-ec2-sg"
  description = "Allow HTTP, SSH, MySQL from Anywhere"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "MySQL"
    from_port   = 3306
    to_port     = 3306
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
    Name = "wordpress-ec2-sg"
  }
}

resource "aws_lb" "main" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ec2_sg.id]
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
  protocol_version = "HTTP1"

  health_check {
    protocol = "HTTP"
    path     = "/"
  }

  stickiness {
    type    = "lb_cookie"
    enabled = true
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
  update_default_version = true
  image_id      = "ami-0dc52b32bb54af3db" 
  instance_type = "t3.large"
  key_name      = "wordpress-vockey-key"

  # vpc_security_group_ids = [aws_security_group.ec2_sg.id] # Handled in network_interfaces below

  iam_instance_profile {
    name = data.aws_iam_instance_profile.lab_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              set -x
              
              # Minimal User Data for Baked AMI
              # The AMI already contains WordPress, PHP, and the Secrets configuration.
              # We just need to ensure the service starts and configure dynamic URLs.
              
              systemctl enable httpd
              systemctl start httpd
              
              # Handle the Load Balancer URL via wp-config.php
              # We append these lines to define the site URL dynamically based on the ALB
              LB_DNS="${aws_lb.main.dns_name}"
              
              # Check if already defined effectively (though appending works if not defined or if we don't care about redefinition notice/failure handling for now, user asked to include it back)
              # Simple append approach as requested:
              echo "define('WP_HOME','http://$LB_DNS');" >> /var/www/html/wp-config.php
              echo "define('WP_SITEURL','http://$LB_DNS');" >> /var/www/html/wp-config.php
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
  vpc_zone_identifier = var.public_subnets
  
  health_check_type         = "ELB"
  health_check_grace_period = 300

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

resource "aws_autoscaling_policy" "cpu" {
  name                   = "target-tracking-policy"
  autoscaling_group_name = aws_autoscaling_group.bar.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}
