variable "region" {
  default = "us-west-2"
}

variable "profile" {
  default = "default"
}

variable "cluster_name" {
  default = "jupyter"
}

variable "map_accounts" {
  description = "Additional AWS account numbers to add to the aws-auth configmap."
  type        = list(string)
  default = [ ]
}

variable "map_roles" {
  description = "Additional IAM roles to add to the aws-auth configmap."
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))

  default = [
  ]
}

variable "map_users" {
  description = "Additional IAM users to add to the aws-auth configmap."
  type = list(object({
    userarn  = string
    username = string
    groups   = list(string)
  }))

  default = [
  ]
}

variable "use_private_subnets" {
    description = "Use private subnets for EKS worker nodes."
    type        = bool
    default     = true
}

variable "public_subnets" {  
    description = "Public subnet IP ranges."
    type        = list(string)
    default     = ["172.16.1.0/24", "172.16.2.0/24", "172.16.3.0/24"]
}

variable "private_subnets" {  
    description = "Private subnet IP ranges."
    type        = list(string)
    default     = ["172.16.4.0/24", "172.16.5.0/24", "172.16.6.0/24"]
}

variable "cidr" {
    description = "IP range of subnets"
    type = string
    default = "172.16.0.0/16"
}