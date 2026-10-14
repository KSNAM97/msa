# 인프라(ECR, EKS 접근 권한, soldesk 네임스페이스/시크릿)가 모두 준비된 뒤
# GitHub Actions 를 수동 실행(workflow_dispatch)해 이미지 5개를 빌드/배포한다. (gh CLI 로그인 필요)
# 끄려면: terraform apply -var trigger_ci=false
resource "terraform_data" "trigger_ci" {
  count = var.trigger_ci ? 1 : 0

  provisioner "local-exec" {
    on_failure  = continue # gh 미설치/미로그인이어도 apply 는 실패시키지 않음 (수동 실행하면 됨)
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    command     = "gh workflow run deploy_ordermsa_with_k8s.yml --repo ${var.github_repo} --ref main"
  }

  depends_on = [
    aws_ecr_repository.app,
    module.eks, # eks-user 접근 권한(access entry) 포함
    kubernetes_namespace.soldesk,
    kubernetes_secret.app,
    kubernetes_secret.aws,
    helm_release.argocd_root,
  ]
}
