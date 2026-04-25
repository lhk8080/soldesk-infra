resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = var.namespace
  create_namespace = true
  version          = var.version

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
      }
      controller = {
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
      }
      repoServer = {
        resources = {
          requests = { cpu = "50m", memory = "128Mi" }
          limits   = { cpu = "200m", memory = "256Mi" }
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
