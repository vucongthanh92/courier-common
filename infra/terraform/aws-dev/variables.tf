variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "project" {
  type    = string
  default = "courier"
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "availability_zone" {
  type    = string
  default = "ap-southeast-2a"
}

variable "admin_cidr" {
  description = "Reserved for a future explicit administrative ingress rule. SSM is the only administrative access in this baseline."
  type        = string
  default     = null
}

variable "budget_alert_email" {
  description = "Email address that receives the AWS Budget and disk-usage alert subscriptions."
  type        = string
  nullable    = false
}

variable "application_instance_type" {
  description = "ARM64 EC2 instance type for K3s, Argo CD, apps, and compact monitoring."
  type        = string
  default     = "t4g.large"
}

variable "data_instance_type" {
  description = "ARM64 EC2 instance type for PostgreSQL, Redis, Kafka, and Qdrant."
  type        = string
  default     = "t4g.medium"
}

variable "application_root_volume_size" {
  type    = number
  default = 25
}

variable "data_root_volume_size" {
  type    = number
  default = 25
}

variable "data_volume_size" {
  type    = number
  default = 60
}

variable "k3s_version" {
  description = "Pinned K3s release installed on the application node."
  type        = string
  default     = "v1.37.1+k3s1"
}

variable "ecr_credential_provider_version" {
  description = "Pinned Kubernetes AWS ECR credential-provider version; keep its minor version aligned with K3s."
  type        = string
  default     = "v1.37.0"
}

variable "sops_age_parameter_name" {
  description = "SSM SecureString holding the AWS dev Argo CD SOPS age private key. Its value is deliberately not managed by Terraform."
  type        = string
  default     = "/courier/dev/argocd/sops-age-key"
}

variable "application_runtime_parameter_path_prefix" {
  description = "SSM Parameter Store prefix containing Courier development runtime configuration that K3s workloads may synchronize through External Secrets Operator."
  type        = string
  default     = "/courier/dev/"
}

variable "github_owner" {
  description = "GitHub owner whose approved main-branch workflows may assume the ECR publishing role."
  type        = string
  default     = "vucongthanh92"
}

variable "github_owner_id" {
  description = "Immutable GitHub numeric ID for github_owner, required by the customized OIDC subject template."
  type        = string
  default     = "25337938"
}

variable "ecr_repositories" {
  description = "Courier service repositories published to private ECR."
  type        = set(string)
  default = [
    "user-service",
    "chat-service",
    "payment-gateway",
    "agent-gateway",
    "conversa-app",
    "flikk-app",
  ]
}

variable "github_repositories" {
  description = "Exact GitHub repositories and immutable numeric IDs allowed to publish Courier images from main."
  type        = map(string)
  default = {
    courier-user-svc        = "1413925694"
    courier-chat-svc        = "1413958684"
    courier-payment-gateway = "1414239516"
    courier-agent-gateway   = "1414225958"
    courier-conversa-app    = "1414218150"
    courier-flikk-app       = "1414261620"
  }
}
