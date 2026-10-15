# =============================================================================
# [addons.tf] 클러스터 안에 설치되는 Helm 애드온 + ArgoCD 부트스트랩(root app)
#   설치 순서(depends_on 으로 보장):
#     EKS -> (autoscaler, metrics-server, ingress-nginx, cert-manager, argocd) -> 시크릿/인증서 복원 -> argocd_root
#   이후 서비스 배포는 테라폼이 아니라 ArgoCD(GitOps)가 repo 의 매니페스트를 읽어 수행한다.
# =============================================================================

# 노드 자동 증감: Pending 파드가 생기면 노드를 늘리고 비면 줄인다 (min/max 는 eks.tf 의 노드 그룹 설정)

resource "helm_release" "autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"

  set {
    name  = "autoDiscovery.clusterName"
    value = module.eks.cluster_name
  }
  # 차트 최신 이미지는 k8s 1.32에 없는 API(DRA)를 조회해 동작 불가 -> 클러스터 버전(1.32)에 맞춤
  set {
    name  = "image.tag"
    value = "v1.32.1"
  }
  set {
    name  = "awsRegion"
    value = var.region
  }
  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }
  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.autoscaler_irsa.iam_role_arn
  }
  depends_on = [module.eks]
}

# 파드 CPU 사용률 수집 (repo 의 HPA 가 이 값을 보고 파드 수를 조절)
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  depends_on = [module.eks]
}

# 외부 진입점: NLB(로드밸런서)를 만들고 도메인별(Host)로 서비스에 라우팅한다. ingress 매니페스트의 class "nginx" 와 연결
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  depends_on       = [module.eks]
}

# Let's Encrypt 인증서 자동 발급/갱신. CRD 를 함께 설치해야 repo 의 Certificate/ClusterIssuer 가 적용된다
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  set {
    name  = "crds.enabled"
    value = "true"
  }
  depends_on = [module.eks]
}

# GitOps 배포 도구. 웹 UI 는 argo.ksnam97.com (ingress 는 repo 의 msa/k8s/k8s-argocd 에서 관리)
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  # repo의 argocd-server-insecure-patch.json 과 동일 (TLS는 ingress에서 종료)
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }
  depends_on = [module.eks]
}

# root app -> repo의 argocd/apps sync (member/product/ordering/apigateway/ingress/hpa/monitoring)
resource "helm_release" "argocd_root" {
  name       = "argocd-root"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  namespace  = "argocd"
  values = [yamlencode({
    applications = {
      msa-root = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.git_repo
          targetRevision = "main"
          path           = "argocd/apps"
        }
        destination = { server = "https://kubernetes.default.svc", namespace = "argocd" }
        syncPolicy  = { automated = { prune = true, selfHeal = true } }
      }
    }
  })]
  # 순서 보장: ArgoCD/ingress/cert-manager 설치 완료 + 앱이 참조할 시크릿(DB/S3) + 복원된 인증서가 먼저 준비돼야 한다
  depends_on = [helm_release.argocd, helm_release.cert_manager, helm_release.ingress_nginx, kubernetes_secret.app, kubernetes_secret.aws, kubernetes_secret.jwt, kubernetes_secret.admin, kubernetes_secret.grafana, kubernetes_secret.adminer_auth, kubernetes_secret.adminer_config, kubernetes_service_account.grafana, terraform_data.restore_certs]
}

# Grafana 서비스어카운트: 위 IAM 역할(grafana_irsa)을 연결해서 Grafana 파드가 CloudWatch 를 읽을 수 있게 한다.
# 계정 ID 가 들어가는 역할 ARN 을 repo 매니페스트에 적지 않으려고 테라폼이 서비스어카운트를 직접 만든다.
# (repo 의 grafana-depl_svc.yml 은 serviceAccountName: grafana 로 이 계정을 사용)
resource "kubernetes_service_account" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = module.grafana_irsa.iam_role_arn
    }
  }
}
