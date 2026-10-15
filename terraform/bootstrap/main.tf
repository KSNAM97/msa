# =============================================================================
# [bootstrap/main.tf] 테라폼 원격 state 저장소 (S3). 한 번만 apply 하고 계속 유지한다.
#
# 왜 필요한가
#   - 테라폼 state 에는 비밀 값(DB 비밀번호, JWT 키, S3 키 등)이 들어 있다. 로컬 파일로 두면 PC 가 고장나면 잃고, 팀/다른 PC 와 공유가 안 된다.
#   - S3 에 두면: 암호화 저장 + 버전 관리(실수로 덮어써도 복구) + 잠금(동시에 apply 하는 사고 방지)
#
# 왜 메인 인프라와 별도 스택인가
#   - 메인 인프라를 destroy 해도 state 버킷이 같이 지워지면 안 된다 (닭과 달걀 문제). 그래서 이 폴더는 자기 state 를 로컬에 두고,
#     버킷에는 prevent_destroy 를 건다. (이 스택의 state 는 비밀이 없고 리소스가 1개라 로컬로 충분하다)
#
# 잠금: 테라폼 1.10+ 의 S3 네이티브 잠금(use_lockfile)을 쓰므로 DynamoDB 테이블이 필요 없다.
#
# 사용:  cd terraform/bootstrap && terraform init && terraform apply
#        그 다음 메인(terraform/)에서  terraform init -migrate-state  (backend.tf 가 이 버킷을 가리킨다)
# =============================================================================
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

variable "region" { default = "ap-northeast-2" }

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "nam97-mall", Environment = "sandbox", ManagedBy = "terraform" }
  }
}

data "aws_caller_identity" "me" {}

# 버킷 이름에 계정 ID 를 넣어 전 세계에서 유일하게 만든다
resource "aws_s3_bucket" "state" {
  bucket = "nam97-tfstate-${data.aws_caller_identity.me.account_id}-${var.region}"

  # state 가 사라지면 인프라를 테라폼으로 관리할 수 없게 되므로 실수로 지워지지 않게 막는다.
  # (정말 지우려면 이 블록을 제거하고 버킷을 비운 뒤 destroy)
  lifecycle {
    prevent_destroy = true
  }
}

# 버전 관리: state 를 잘못 덮어써도 이전 버전으로 되돌릴 수 있다
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 저장 시 암호화 (비밀 값이 들어 있으므로 필수)
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 인터넷 공개 완전 차단
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# HTTPS 가 아닌 접근은 거부 (전송 구간 암호화 강제)
resource "aws_s3_bucket_policy" "tls_only" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.state]
}

# 오래된 이전 버전은 90일 뒤 정리 (현재 버전은 유지). 비용이 늘지 않게 한다
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
  depends_on = [aws_s3_bucket_versioning.state]
}

output "state_bucket" { value = aws_s3_bucket.state.bucket }
