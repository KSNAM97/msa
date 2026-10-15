# =============================================================================
# [backend.tf] 테라폼 state 를 S3 에 저장 (원격 backend)
#   - 버킷은 terraform/bootstrap 스택이 만든다 (암호화 + 버전 관리 + 공개 차단 + HTTPS 전용). 메인을 destroy 해도 유지된다.
#   - use_lockfile: S3 네이티브 잠금(테라폼 1.10+). 동시에 apply 하면 한쪽이 대기/실패해서 state 가 깨지지 않는다. DynamoDB 불필요
#   - backend 블록에는 변수를 쓸 수 없어서 버킷 이름을 직접 적는다 (계정 ID 는 비밀이 아님)
#   - 다른 PC 에서 시작:  git clone 후  terraform init  (AWS 자격 증명만 있으면 같은 state 를 읽는다)
# =============================================================================
terraform {
  backend "s3" {
    bucket       = "nam97-tfstate-872792314844-ap-northeast-2"
    key          = "nam97/main/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
