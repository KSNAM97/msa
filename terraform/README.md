# aws-msa-backend Terraform (ksnam97.com)

```powershell
terraform init
terraform apply        # 약 15~25분
aws eks update-kubeconfig --name my-cluster --region ap-northeast-2
```

- 생성: VPC, EKS(my-cluster), RDS MySQL(ordermsa), ECR 4개, ingress-nginx, cert-manager, ArgoCD(+root app), cluster-autoscaler, metrics-server, Route53 CNAME(server/argo/prometheus/grafana.ksnam97.com), secret `my-app-secrets`.
- apply 후 `.\sync-backend.ps1` 실행 -> ECR 계정ID, S3 버킷명, CORS 도메인을 aws-msa-backend 파일에 자동 반영.
- 이미지는 ECR에 push 필요(GitHub Actions). manifest의 ECR 계정ID(872792314844)가 본인 계정과 같아야 함.
- Route53: 기존 ksnam97.com 존을 그대로 사용(NS/SOA/기존 레코드 불변), CNAME 4개만 생성/삭제. 도메인 NS는 건드리지 않음.
