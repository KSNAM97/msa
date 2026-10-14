# =============================================================================
# [outputs.tf] apply 후 확인용 값 (terraform output <이름> 으로 조회)
# =============================================================================
output "kubeconfig_cmd" { value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}" } # kubectl 접속 설정
output "ecr_urls" { value = { for k, v in aws_ecr_repository.app : k => v.repository_url } }                             # 이미지 push 대상
output "account_id" { value = data.aws_caller_identity.me.account_id }                                                   # sync-backend.ps1 이 사용
output "s3_bucket" { value = aws_s3_bucket.images.bucket }                                                               # sync-backend.ps1 이 사용
output "rds_endpoint" { value = aws_db_instance.this.address }
output "argocd_admin_pw_cmd" { value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath={.data.password} | base64 -d" }
