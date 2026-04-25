variable "env" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }

variable "db_password" {
  type      = string
  sensitive = true
}

variable "writer_instance_class" {
  type        = string
  description = "RDS writer 인스턴스 타입"
}

variable "allocated_storage" {
  type        = number
  description = "초기 할당 GB"
}

variable "max_allocated_storage" {
  type        = number
  description = "스토리지 자동 확장 상한 GB (0이면 비활성)"
  default     = 0
}
