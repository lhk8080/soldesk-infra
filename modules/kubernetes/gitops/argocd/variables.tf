variable "namespace" {
  type    = string
  default = "argocd"
}

variable "chart_version" {
  type    = string
  default = "7.8.26"
}

# bcrypt 해시. 기본값: soldesk1.
# argocd account bcrypt --password 'YOUR_PASSWORD' 로 갱신
variable "root_password_bcrypt" {
  type      = string
  sensitive = true
  default   = "$2a$10$0Sn244C61FveDwgHGeC2qe/8TAcl7j6NN2MpQe9rDSFZwYp1sk4i6"
}
