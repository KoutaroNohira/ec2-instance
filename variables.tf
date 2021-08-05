variable "region" {
  default = "ap-northeast-1"
}

variable "vpc-cidr-block" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type    = list(any)
  default = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "public-cidr-blocks" {
  type    = list(any)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "ingress-public" {
  description = "Ingress CIDR IP"
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance-type" {
  default = "t2.micro"
}

variable "instance-count" {
  default = 2
}
