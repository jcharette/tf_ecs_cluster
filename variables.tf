variable "name" {
  description = "Name of Cluster"
  type        = "string"
}

variable "project" {
  description = "Name of Project for log stream"
}

variable "instance_type" {
  description = "Type of instance to provision"
  default     = "m3.large"
}

variable "aws_region" {
  description = "AWS Region to build in"
  default     = "us-east-1"
}

variable "key_name" {
  description = "AWS key to use for instances"
}

variable "vpc_id" {
  description = "VPC ID to place nodes in"
}

variable "asg_min" {
  description = "Min number of nodes in Autoscaling group"
  default     = "1"
}

variable "asg_max" {
  description = "Max number of nodes in Autoscaling group"
  default     = "10"
}

variable "asg_desired" {
  description = "Desired number of nodes in ASG"
  default     = "2"
}

variable "vpc_subnet_ids" {
  description = "List of VPC Subnet ID's to map ASG nodes to"
  type        = "list"
}

variable "node_root_disk_size" {
  description = "Size of root disk for ECS nodes"
  default     = 60
}
