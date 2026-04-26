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
        ingress = {
          enabled          = true
          ingressClassName = "alb"
          annotations = {
            "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"      = "ip"
            "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\":80}]"
            "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
            "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
          }
          hostname = ""
          paths    = ["/"]
          pathType = "Prefix"
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
