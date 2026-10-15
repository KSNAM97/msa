# =============================================================================
# [variables.tf] 환경에 따라 바뀔 수 있는 값. 대부분 기본값으로 충분하다.
#   바꿀 때: terraform apply -var node_instance_type=t3.large  (또는 terraform.tfvars, 단 git 에는 올리지 않는다)
# =============================================================================
variable "region" { default = "ap-northeast-2" }
variable "cluster_name" { default = "my-cluster" } # GitHub Actions 워크플로(update-kubeconfig)의 클러스터 이름과 같아야 함
variable "k8s_version" { default = "1.32" }        # cluster-autoscaler 이미지 버전(addons.tf)도 이 버전에 맞춰야 함
variable "node_instance_type" { default = "t3.medium" }
variable "ci_user" { default = "eks-user" }                            # GitHub Actions 가 쓰는 IAM 사용자 (eks.tf 에서 접근 권한 부여)
variable "domain" { default = "ksnam97.com" }                          # 기존 Route53 호스팅 존 이름 (dns.tf: 존은 만들지 않고 조회만 함)
variable "github_repo" { default = "KSNAM97/msa" }                     # gh CLI 용 owner/repo (ci.tf)
variable "trigger_ci" { default = true }                               # apply 완료 후 GitHub Actions 자동 실행 (ci.tf)
variable "git_repo" { default = "https://github.com/KSNAM97/msa.git" } # ArgoCD 가 읽을 리포 (공개 리포)
variable "db_instance_class" { default = "db.t4g.micro" }              # RDS 샌드박스: 가장 작은 인스턴스 (data.tf 의 RDS 설명 참고)
variable "api_allowed_cidrs" { default = ["0.0.0.0/0"] }               # EKS API 서버 접근 허용 대역. CI(GitHub Actions)가 접속하므로 기본은 전체. 로컬만 쓸 때는 ["내IP/32"]
