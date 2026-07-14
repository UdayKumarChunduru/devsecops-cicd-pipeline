variable "cluster_name" {
  type = string
}

variable "cluster_version" {
  type    = string
  default = "1.36"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "node_instance_type" {
  type    = string
  default = "t3.small"
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_volume_size" {
  type    = number
  default = 20
}
