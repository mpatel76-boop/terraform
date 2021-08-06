# AWS Access Creds

provider "aws" {
  region     = "eu-west-1"
  access_key = "*******"
  secret_key = "*******"
}

# cidr of existing VPC use to import

resource "aws_vpc" "main" {
  cidr_block = "10.24.0.0/16"
}

resource "aws_subnet" "public_eu_west_1a" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.24.4.0/24"
  availability_zone = "eu-west-1a"

  tags = {
    Name = "Public Subnet eu-west-1a"
  }
}

resource "aws_subnet" "public_eu_west_1b" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.24.5.0/24"
  availability_zone = "eu-west-1b"

  tags = {
    Name = "Public Subnet eu-west-1b"
  }
}

# Sec group for ASG

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound connections"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Allow SSH Security Group"
  }
}

  resource "aws_launch_configuration" "eval" {
  name_prefix = "eval-"

  image_id = "ami-0af21c037dd8874e9"
  instance_type = "t2.micro"

  security_groups = [ aws_security_group.allow_ssh.id ]
  associate_public_ip_address = true

  lifecycle {
    create_before_destroy = true
  }
}

# NLB creation

resource "aws_lb" "test" {
  name               = "test-lb-tf"
  internal           = false
  load_balancer_type = "network"
  subnets            = [
    aws_subnet.public_eu_west_1a.id,
    aws_subnet.public_eu_west_1b.id
  ]

  enable_deletion_protection = true

  tags = {
    Environment = "eval"
  }
}

# ASG creation

resource "aws_autoscaling_group" "eval" {
  name = "${aws_launch_configuration.eval.name}-asg"

  min_size             = 1
  desired_capacity     = 2
  max_size             = 3

target_group_arns = ["${aws_lb_target_group.test.arn}"]
  launch_configuration = aws_launch_configuration.eval.name

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]

  metrics_granularity = "1Minute"

  vpc_zone_identifier  = [
    aws_subnet.public_eu_west_1a.id,
    aws_subnet.public_eu_west_1b.id
  ]

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "eval"
    propagate_at_launch = true
  }

}

# Target group for NLB

resource "aws_lb_target_group" "test" {
  name     = "test"
  protocol = "TCP"
  port     = 22
  vpc_id      = "${aws_vpc.main.id}"

  health_check {
      healthy_threshold   = 2
      unhealthy_threshold = 2
      interval            = 10
  }
}

# Listener for NLB

resource "aws_lb_listener" "ssh" {
  load_balancer_arn = "${aws_lb.test.arn}"
  port              = "22"
  protocol          = "TCP"

  default_action {
    target_group_arn = "${aws_lb_target_group.test.arn}"
    type             = "forward"
  }
}


# CloudWatch monitoring to detect Healthy Hosts

resource "aws_sns_topic" "health" {
  name = "health-topic"
}

resource "aws_cloudwatch_metric_alarm" "nlb_healthyhosts" {
  alarm_name          = "alarmname"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/NetworkELB"
  period              = "60"
  statistic           = "Average"
  threshold           = var.logstash_servers_count
  alarm_description   = "Number of healthy nodes in Target Group"
  actions_enabled     = "true"
  alarm_actions       = [aws_sns_topic.health.arn]
  ok_actions          = [aws_sns_topic.health.arn]
  dimensions = {
    TargetGroup  = aws_lb_target_group.test.arn_suffix
    LoadBalancer = aws_lb.test.arn_suffix
  }
}