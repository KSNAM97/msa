# =============================================================================
# [cloudtrail.tf] CloudTrail: 누가 언제 어떤 AWS API 를 호출했는지(생성/삭제/실패) 기록해 S3 에 보관한다.
#   - CloudWatch 는 "지금 상태(CPU 등)", CloudTrail 은 "작업 이력(누가 무엇을 했나)" 을 본다.
#   - 관리 이벤트(리소스 생성/삭제/변경)만 기록한다. 첫 번째 관리 이벤트 추적은 무료, 로그는 S3 에 저장(소량이라 비용 거의 없음).
#   - destroy 시 로그가 들어 있어도 지워지도록 force_destroy = true (연습용 구성)
# =============================================================================
locals {
  trail_name   = "${var.cluster_name}-trail"
  trail_bucket = "${var.cluster_name}-cloudtrail-${data.aws_caller_identity.me.account_id}-${var.region}"
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = local.trail_bucket
  force_destroy = true
}

# 로그 버킷은 외부 공개 금지
resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 저장 시 암호화(SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# 오래된 로그는 자동 삭제 (보관 30일)
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}
    expiration { days = 30 }
  }
}

# CloudTrail 서비스가 이 버킷에 로그를 쓸 수 있게 허용 (이 trail 에서 오는 요청만)
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # 보안: HTTP(암호화 없음) 요청은 모두 거부
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.cloudtrail.arn, "${aws_s3_bucket.cloudtrail.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "AclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
        Condition = { StringEquals = { "aws:SourceArn" = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.me.account_id}:trail/${local.trail_name}" } }
      },
      {
        Sid       = "Write"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.me.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.me.account_id}:trail/${local.trail_name}"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "this" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true  # IAM 같은 전역 서비스 작업도 기록
  is_multi_region_trail         = false # 이 리전만 (단일 리전 추적, 비용 절감)
  enable_log_file_validation    = true  # 로그 변조 검증

  event_selector {
    read_write_type           = "WriteOnly" # 변경(쓰기) 작업만 기록: 읽기까지 기록하면 양이 많아진다
    include_management_events = true
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
