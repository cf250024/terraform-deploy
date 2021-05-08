resource "kubernetes_namespace" "jhub" {
  metadata {
    name = "jhub"
  }
}

resource "helm_release" "jupyterhub" {
  name = "jupyterhub"
  namespace = kubernetes_namespace.jhub.metadata.0.name
  repository = "https://jupyterhub.github.io/helm-chart"
  chart = "jupyterhub"
  version = "0.11.1"

  values = [
    file("jupyterhubvalues.yaml")
  ]
}
