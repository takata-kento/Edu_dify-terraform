variable "region" {
  description = "The region in which the resources will be created."
  default     = "ap-northeast-1"
  type        = string
}

variable "dify_storage_bucket" {
  description = "The name of the S3 bucket to create for storing Dify data."
  type        = string
}

variable "vpc_id" {
  description = "The ID of the VPC in which the resources will be created."
  type        = string
}

variable "private_subnet_ids" {
  description = "The IDs of the private subnets in which the resources will be created."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "The IDs of the private subnets in which the resources will be created."
  type        = list(string)
}

variable "dify_api_version" {
  description = "The version of the Dify API to deploy."
  type        = string
}

variable "dify_web_version" {
  description = "The version of the Dify web to deploy."
  type        = string
}

variable "dify_sandbox_version" {
  description = "The version of the Dify sandbox to deploy."
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "The CIDR blocks from which traffic is allowed to the Dify API."
  type        = list(string)

}
