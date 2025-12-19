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
  image_id      = "ami-043927849594c25e3" 
  instance_type = "t3.micro"
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
              sleep 30

              # 1. Install necessary tools and dependencies
              export DEBIAN_FRONTEND=noninteractive
              apt-get update
              apt-get install -y apache2 php libapache2-mod-php php-mysql wget php-xml php-curl unzip git

              # 2. Install Composer
              curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

              # 3. Get WordPress
              cd /var/www/html
              rm -f index.html
              wget https://wordpress.org/latest.tar.gz
              tar -xzf latest.tar.gz --strip-components=1
              cp wp-config-sample.php wp-config.php

              # 4. Install AWS SDK for PHP
              cd /var/www/html
              composer require aws/aws-sdk-php

              # 5. Create Secrets Fetching Script
              cat << 'PHP_EOF' > /var/www/html/aws-secrets.php
              <?php
              require 'vendor/autoload.php';

              use Aws\SecretsManager\SecretsManagerClient;
              use Aws\Exception\AwsException;

              $client = new SecretsManagerClient([
                  'version' => 'latest',
                  'region'  => 'us-east-1', // Adjust if needed
              ]);

              $secretName = 'wordpress-db-credentials';

              try {
                  $result = $client->getSecretValue([
                      'SecretId' => $secretName,
                  ]);
              } catch (AwsException $e) {
                  // Fallback or error handling
                  error_log($e->getMessage());
                  exit;
              }

              if (isset($result['SecretString'])) {
                  $secret = $result['SecretString'];
              } else {
                  $secret = base64_decode($result['SecretBinary']);
              }

              $creds = json_decode($secret, true);

              define('DB_NAME',     $creds['dbname']);
              define('DB_USER',     $creds['username']);
              define('DB_PASSWORD', $creds['password']);
              define('DB_HOST',     $creds['host']);
              ?>
              PHP_EOF

              # 6. Configure wp-config.php to use the secrets script
              # Remove the default define lines for DB constants
              sed -i "/define( 'DB_NAME'/d" wp-config.php
              sed -i "/define( 'DB_USER'/d" wp-config.php
              sed -i "/define( 'DB_PASSWORD'/d" wp-config.php
              sed -i "/define( 'DB_HOST'/d" wp-config.php

              # Inject require statement at the top
              sed -i "1s/^/<?php require_once 'aws-secrets.php'; ?>\n/" wp-config.php
              # Remove the opening <?php from the original file since we added one
              sed -i '2s/<?php//' wp-config.php

              # 7. Handle the Load Balancer URL via wp-config.php
              LB_DNS="${aws_lb.main.dns_name}"
              echo "define('WP_HOME','http://$LB_DNS');" >> wp-config.php
              echo "define('WP_SITEURL','http://$LB_DNS');" >> wp-config.php

              # 8. Finalize
              chown -R www-data:www-data /var/www/html
              systemctl enable apache2
              systemctl start apache2
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
