variable "env" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }

variable "node_type" {
  type        = string
  description = "단일 노드 ElastiCache 인스턴스 타입"
}
