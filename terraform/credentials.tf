# =============================================================================
# [credentials.tf] apply 가 끝날 때 접속 주소와 비밀번호를 리포 루트의 password.txt 에 자동 저장
#   - password.txt 는 루트 .gitignore 로 git 에서 제외된다 (내 PC 에만 남음)
#   - 실행 내용은 scripts/show-credentials.ps1 -Save 와 같다. 비밀번호는 테라폼이 환경변수로 직접 넘긴다
#     (apply 도중에는 terraform output 을 읽을 수 없기 때문). 환경변수는 민감 값이라 apply 로그에 출력되지 않는다.
#   - 비밀번호가 바뀔 때(= apply 로 새로 만들어질 때)마다 다시 저장된다
#   - 끄려면 이 파일을 지우거나 resource 를 주석 처리. PC 에 PowerShell 과 aws/kubectl 이 있어야 ArgoCD 비밀번호까지 저장됨
# =============================================================================
resource "terraform_data" "save_credentials" {
  triggers_replace = [random_password.admin.result, random_password.grafana.result, random_password.adminer.result, random_password.db.result]

  provisioner "local-exec" {
    on_failure  = continue # 저장에 실패해도 apply 자체는 실패시키지 않음 (나중에 .\scripts\show-credentials.ps1 -Save 로 수동 저장)
    interpreter = ["PowerShell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
    command     = "& '${abspath(path.module)}/scripts/show-credentials.ps1' -Save -Domain '${var.domain}' -Cluster '${var.cluster_name}' -Region '${var.region}' | Out-Null"
    environment = {
      TF_ADMIN_PW   = random_password.admin.result
      TF_GRAFANA_PW = random_password.grafana.result
      TF_ADMINER_PW = random_password.adminer.result
      TF_DB_PW      = random_password.db.result
    }
  }

  # 모든 구성(ArgoCD 가 뜬 뒤)이 끝난 다음에 실행: ArgoCD 초기 비밀번호 시크릿이 있어야 한다
  depends_on = [helm_release.argocd_root, kubernetes_secret.admin, kubernetes_secret.grafana, kubernetes_secret.adminer_auth]
}
