# destroy 시 테라폼 밖에서 만들어진 것(ArgoCD가 배포한 리소스, ingress가 만든 NLB)이 남아
# 네임스페이스/VPC 삭제가 막히는 문제를 막는다. (aws cli, kubectl 필요)

# 1) ArgoCD 앱/ingress/네임스페이스를 먼저 정리 (argocd_root 보다 먼저 destroy 됨)
resource "terraform_data" "pre_destroy" {
  input = { cluster = module.eks.cluster_name, region = var.region, backup_dir = local.cert_backup_dir }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    command     = <<-EOT
      aws eks update-kubeconfig --name ${self.input.cluster} --region ${self.input.region}
      # 발급된 TLS 인증서 시크릿 백업 (Let's Encrypt 발급 한도 회피, 다음 apply 때 복원)
      $d = '${self.input.backup_dir}'
      New-Item -ItemType Directory -Force $d | Out-Null
      foreach ($s in 'argocd/argo-ksnam97-com-tls', 'monitoring/monitoring-ksnam97-com-tls', 'soldesk/server-ksnam97-com-tls', 'monitoring/db-ksnam97-com-tls') {
        $ns, $n = $s -split '/'
        $j = kubectl -n $ns get secret $n -o json 2>$null
        if (-not $j) { continue }
        $o = $j | ConvertFrom-Json
        if (-not $o.data.'tls.crt') { continue }
        $bk = @{ apiVersion = 'v1'; kind = 'Secret'; type = $o.type; data = $o.data; metadata = @{ name = $n; namespace = $ns; annotations = $o.metadata.annotations; labels = $o.metadata.labels } }
        [IO.File]::WriteAllText("$d\$ns-$n.json", ($bk | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
      }
      kubectl delete applications.argoproj.io --all -n argocd --timeout=60s
      kubectl delete ingress --all -A --timeout=120s
      kubectl delete ns soldesk monitoring --ignore-not-found --timeout=180s
    EOT
  }

  depends_on = [helm_release.argocd_root, kubernetes_namespace.soldesk, kubernetes_namespace.monitoring]
}

# 2) ingress-nginx 삭제 후 로드밸런서가 완전히 사라질 때까지 대기 (vpc 삭제 전)
resource "terraform_data" "wait_lb_gone" {
  input = { vpc_id = module.vpc.vpc_id, region = var.region }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    command     = <<-EOT
      # 이 VPC 안의 로드밸런서를 모두 센다: ALB/NLB(elbv2) + 클래식 ELB(elb). 둘 다 0 이 될 때까지 최대 10분 대기
      # (예전에는 elbv2 만 확인해서, 클래식 ELB 일 때는 기다리지 않고 지나가 VPC 삭제가 막힐 수 있었다)
      for ($i = 0; $i -lt 30; $i++) {
        $v2 = aws elbv2 describe-load-balancers --region ${self.input.region} --query "length(LoadBalancers[?VpcId=='${self.input.vpc_id}'])" --output text
        $cl = aws elb describe-load-balancers --region ${self.input.region} --query "length(LoadBalancerDescriptions[?VPCId=='${self.input.vpc_id}'])" --output text
        if (($v2 -eq '0') -and ($cl -eq '0')) { break }
        Start-Sleep -Seconds 20
      }
    EOT
  }

  depends_on = [helm_release.ingress_nginx, module.vpc]
}
