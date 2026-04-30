variable "domain_name" {
  description = "주 도메인 (예: hk99.shop)"
  type        = string
}

variable "subject_alternative_names" {
  description = "추가 도메인 (예: [\"*.hk99.shop\"])"
  type        = list(string)
  default     = []
}

variable "zone_id" {
  description = "DNS 검증 CNAME을 추가할 Route53 hosted zone ID"
  type        = string
}
