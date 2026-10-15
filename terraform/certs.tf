# TLS 인증서 백업(destroy 시 cleanup.tf) / 복원(apply 시, ArgoCD root app 보다 먼저)
# Let's Encrypt 는 같은 도메인 조합을 7일에 5회까지만 발급하므로, 이전에 발급된 인증서를 재사용한다.
# cert-backup/ 에는 개인키가 들어 있으므로 git 에 올리지 않는다 (.gitignore 처리됨).

locals {
  cert_backup_dir = abspath("${path.module}/cert-backup")
}

resource "terraform_data" "restore_certs" {
  provisioner "local-exec" {
    on_failure  = continue # 백업이 없거나 실패해도 apply 는 계속 (cert-manager 가 새로 발급)
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    command     = <<-EOT
      $d = '${local.cert_backup_dir}'
      if (-not (Test-Path $d)) { Write-Host 'no cert backup, skip'; exit 0 }
      aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}
      foreach ($f in Get-ChildItem $d -Filter *.json) {
        $ns = (Get-Content $f.FullName -Raw | ConvertFrom-Json).metadata.namespace
        kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
        kubectl apply -f $f.FullName
      }
    EOT
  }

  depends_on = [helm_release.cert_manager, helm_release.argocd, kubernetes_namespace.ksnam97, kubernetes_namespace.monitoring]
}
