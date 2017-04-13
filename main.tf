resource "aws_ecs_cluster" "main" {
  name = "${var.name}"
}

# generate CoreOS cloud config from template
data "template_file" "cloud_config" {
  template = "${file("${path.module}/cloud-config.yml")}"

  vars {
    aws_region         = "${var.aws_region}"
    ecs_cluster_name   = "${var.name}"
    ecs_log_level      = "info"
    ecs_agent_version  = "latest"
    ecs_log_group_name = "${aws_cloudwatch_log_group.ecs.name}"
  }
}

# use aws_ami provider to find latest CoreOS version
data "aws_ami" "stable_coreos" {
  most_recent = true

  filter {
    name   = "description"
    values = ["CoreOS stable *"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["595879546273"] # CoreOS
}

resource "aws_launch_configuration" "app" {
  security_groups = [
    "${aws_security_group.instance_sg.id}",
  ]

  name_prefix                 = "ECS-Node-${var.name}-"
  key_name                    = "${var.key_name}"
  image_id                    = "${data.aws_ami.stable_coreos.id}"
  instance_type               = "${var.instance_type}"
  iam_instance_profile        = "${aws_iam_instance_profile.app.name}"
  user_data                   = "${data.template_file.cloud_config.rendered}"
  associate_public_ip_address = false

  lifecycle {
    create_before_destroy = true
  }

  root_block_device {
    volume_size           = "${var.node_root_disk_size}"
    delete_on_termination = true
  }
}

resource "aws_security_group" "instance_sg" {
  description = "controls direct access to application instances"
  vpc_id      = "${var.vpc_id}"
  name        = "${var.name}-instsg"

  ingress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]

    /*
    security_groups = [
      "${aws_security_group.lb_sg.id}",
    ]
*/
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_autoscaling_group" "app" {
  depends_on           = ["aws_launch_configuration.app"]
  name                 = "ECS-${var.name}-asg"
  vpc_zone_identifier  = ["${var.vpc_subnet_ids}"]
  min_size             = "${var.asg_min}"
  max_size             = "${var.asg_max}"
  desired_capacity     = "${var.asg_desired}"
  launch_configuration = "${aws_launch_configuration.app.name}"

  tag {
    key                 = "Name"
    value               = "ECS-${var.name}-Node"
    propagate_at_launch = "true"
  }
}

resource "aws_autoscaling_policy" "cpu-scale-up" {
  name                   = "ECS-${var.name}-cpu-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = "${aws_autoscaling_group.app.name}"

  depends_on = [
    "aws_autoscaling_group.app",
  ]
}

resource "aws_autoscaling_policy" "cpu-scale-down" {
  name                   = "ECS-${var.name}-cpu-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = "${aws_autoscaling_group.app.name}"

  depends_on = [
    "aws_autoscaling_group.app",
  ]
}

resource "aws_cloudwatch_metric_alarm" "cpu-high" {
  alarm_name          = "cpu-util-high-ECS-${var.name}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CpuUtilization"
  namespace           = "System/Linux"
  period              = "300"
  statistic           = "Average"
  threshold           = "50"
  alarm_description   = "This metric monitors ec2 cpu for high utilization on ECS hosts"

  alarm_actions = [
    "${aws_autoscaling_policy.cpu-scale-up.arn}",
  ]

  dimensions {
    AutoScalingGroupName = "${aws_autoscaling_group.app.name}"
  }

  depends_on = [
    "aws_autoscaling_group.app",
  ]
}

resource "aws_cloudwatch_metric_alarm" "cpu-low" {
  alarm_name          = "cpu-util-low-ECS-${var.name}"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CpuUtilization"
  namespace           = "System/Linux"
  period              = "300"
  statistic           = "Average"
  threshold           = "15"
  alarm_description   = "This metric monitors ec2 cpu for low utilization on ECS hosts"

  alarm_actions = [
    "${aws_autoscaling_policy.cpu-scale-down.arn}",
  ]

  dimensions {
    AutoScalingGroupName = "${aws_autoscaling_group.app.name}"
  }

  depends_on = [
    "aws_autoscaling_group.app",
  ]
}

resource "aws_autoscaling_policy" "mem-scale-up" {
  name                   = "ECS-${var.name}-mem-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = "${aws_autoscaling_group.app.name}"

  depends_on = [
    "aws_autoscaling_group.app",
  ]
}

resource "aws_autoscaling_policy" "mem-scale-down" {
  name                   = "ECS-${var.name}-mem-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = "${aws_autoscaling_group.app.name}"

  depends_on = [
    "aws_autoscaling_group.app",
  ]
}

resource "aws_cloudwatch_metric_alarm" "memory-high" {
  alarm_name          = "mem-util-high-ECS-${var.name}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "System/Linux"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 memory for high utilization on ECS hosts"

  alarm_actions = [
    "${aws_autoscaling_policy.mem-scale-up.arn}",
  ]

  dimensions {
    AutoScalingGroupName = "${aws_autoscaling_group.app.name}"
  }

  depends_on = [
    "aws_autoscaling_group.app",
  ]
}

resource "aws_cloudwatch_metric_alarm" "memory-low" {
  alarm_name          = "mem-util-low-ECS-${var.name}"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "System/Linux"
  period              = "300"
  statistic           = "Average"
  threshold           = "40"
  alarm_description   = "This metric monitors ec2 memory for low utilization on ECS hosts"

  alarm_actions = [
    "${aws_autoscaling_policy.mem-scale-down.arn}",
  ]

  dimensions {
    AutoScalingGroupName = "${aws_autoscaling_group.app.name}"
  }

  depends_on = [
    "aws_autoscaling_group.app",
  ]
}
