resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = var.namespace
  create_namespace = true
  version          = var.chart_version

  wait            = true
  timeout         = 300
  atomic          = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      global = {
        priorityClassName = "ticketing-priority-platform"
      }
      configs = {
        params = {
          "server.insecure" = true
        }
        cm = {
          "admin.enabled"   = "false"
          "accounts.root"   = "login"
        }
        rbac = {
          "policy.csv"     = "g, root, role:admin"
          "policy.default" = ""
        }
        secret = {
          extra = {
            "accounts.root.password" = var.root_password_bcrypt
          }
        }
      }
      server = {
        service = { type = "ClusterIP" }
        resources = {
          requests = { cpu = "50m", memory = "128Mi" }
          limits   = { cpu = "200m", memory = "256Mi" }
        }
        # Ingress 는 별도 리소스로 관리 (host 없는 catch-all). 차트 ingress 는 hostname 비어있어도 argocd.example.com fallback 박힘.
        ingress = {
          enabled = false
        }
      }
      controller = {
        resources = {
          requests = { cpu = "100m", memory = "512Mi" }
          limits   = { cpu = "500m", memory = "1Gi" }
        }
      }
      repoServer = {
        resources = {
          requests = { cpu = "100m", memory = "512Mi" }
          limits   = { cpu = "500m", memory = "1Gi" }
        }
      }
      redis = {
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { cpu = "200m", memory = "128Mi" }
        }
      }
      applicationSet = { enabled = false }
      notifications  = { enabled = false }
      dex            = { enabled = false }
    })
  ]
}

resource "kubernetes_ingress_v1" "argocd_server" {
  depends_on = [helm_release.argocd]

  metadata {
    name      = "argocd-server"
    namespace = var.namespace
    annotations = {
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\":80}]"
      "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
    }
  }

  spec {
    ingress_class_name = "alb"
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port { number = 80 }
            }
          }
        }
      }
    }
  }
}
