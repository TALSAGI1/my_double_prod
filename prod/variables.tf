############################################
# Global / Region
############################################
variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

############################################
# VPC
############################################
variable "vpc_cidr" {
  description = "CIDR for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability Zones for subnets"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]
}

variable "public_subnets" {
  description = "Public subnets CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "Private subnets CIDRs"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

############################################
# EKS
############################################
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "nova-eks"
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Min number of worker nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Max number of worker nodes"
  type        = number
  default     = 4
}

############################################
# ECR
############################################
variable "ecr_repo_names" {
  description = "List of ECR repositories to create"
  type        = list(string)
  default     = ["guest-app"]
}

############################################
# Monitoring (Prometheus/Grafana)
############################################
variable "grafana_admin_password" {
  description = "Initial Grafana admin password"
  type        = string
  sensitive   = true
  default     = "ChangeMe123!"
}

variable "prometheus_storage_size" {
  description = "PVC size for Prometheus data"
  type        = string
  default     = "20Gi"
}

variable "storage_class_name" {
  description = "K8s StorageClass to use for Prometheus PVC"
  type        = string
  default     = "gp3"
}

############################################
# Load Balancing (optional)
############################################
variable "enable_alb_controller" {
  description = "Install AWS Load Balancer Controller (ALB) via Helm"
  type        = bool
  default     = false
}

############################################
# Tags (optional)
############################################
variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {
    env     = "prod"
    project = "my_double_prod"
  }
}
