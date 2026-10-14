# ECR, S3, RDS, IAM 키, 앱 시크릿

locals {
  apps = ["apigateway", "member-service", "product-service", "ordering-service", "frontend-service"]
}

# ---------- ECR ----------
resource "aws_ecr_repository" "app" {
  for_each     = toset(local.apps)
  name         = each.key
  force_delete = true
}

# ---------- S3 (상품 이미지) ----------
data "aws_caller_identity" "me" {}

resource "aws_s3_bucket" "images" {
  bucket        = "ksnam97-frontend-image-${data.aws_caller_identity.me.account_id}-${var.region}" # "-an" 접미사는 account-regional 전용(헤더 필요)이라 제외
  force_destroy = true
}

# 상품 이미지는 브라우저의 <img> 가 S3 URL 로 직접 읽는다. 버킷이 비공개면 403 으로 이미지가 깨지므로
# "products/ 하위 객체의 읽기(GetObject)"만 공개한다. (업로드/삭제/목록은 아래 IAM 사용자만 가능)
resource "aws_s3_bucket_public_access_block" "images" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true # ACL 기반 공개는 계속 차단
  ignore_public_acls      = true
  block_public_policy     = false # 아래 버킷 정책으로 공개하려면 해제해야 함
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "images_public_read" {
  bucket = aws_s3_bucket.images.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadProductImages"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"                           # 읽기만 허용 (최소 권한)
      Resource  = "${aws_s3_bucket.images.arn}/products/*" # product-service 가 올리는 경로(products/)로 한정
    }]
  })
  # 공개 차단 설정이 먼저 풀려 있어야 정책 적용이 성공한다
  depends_on = [aws_s3_bucket_public_access_block.images]
}

# product-service 가 S3 에 접근할 때 쓰는 IAM 사용자 (키는 아래에서 k8s 시크릿 aws-secret 으로 전달)
resource "aws_iam_user" "s3" { name = "${var.cluster_name}-s3-user" }

resource "aws_iam_user_policy" "s3" {
  user = aws_iam_user.s3.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"], Resource = "${aws_s3_bucket.images.arn}/*" },
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.images.arn }
    ]
  })
}

resource "aws_iam_access_key" "s3" { user = aws_iam_user.s3.name }

# ---------- RDS (MySQL) ----------
resource "random_password" "db" {
  length  = 20
  special = false
}

# RDS 는 private 서브넷에 두고 EKS 노드 보안그룹에서 오는 3306 만 허용 (인터넷/VPC 밖 접근 불가)
# 비밀번호는 random_password 로 생성해 k8s 시크릿(my-app-secrets)으로만 전달 -> 코드/리포에 노출되지 않음
resource "aws_security_group" "rds" {
  name   = "${var.cluster_name}-rds"
  vpc_id = module.vpc.vpc_id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.cluster_name}-db"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_db_instance" "this" {
  identifier             = "${var.cluster_name}-mysql"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "ordermsa"
  username               = "admin"
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  # 학습/개발용 설정: destroy 시 최종 스냅샷 없이 바로 삭제. 운영에서는 true/false 를 반대로 바꿀 것
  skip_final_snapshot = true
  deletion_protection = false
  publicly_accessible = false
}

# ---------- k8s 네임스페이스 / 시크릿 (manifest의 secretKeyRef) ----------
resource "kubernetes_namespace" "soldesk" {
  metadata { name = "soldesk" }
  depends_on = [module.eks]
}

resource "kubernetes_secret" "app" {
  metadata {
    name      = "my-app-secrets"
    namespace = kubernetes_namespace.soldesk.metadata[0].name
  }
  data = {
    DB_HOST = aws_db_instance.this.address
    DB_PW   = random_password.db.result
  }
}

resource "kubernetes_secret" "aws" {
  metadata {
    name      = "aws-secret"
    namespace = kubernetes_namespace.soldesk.metadata[0].name
  }
  data = {
    AWS_ACCESS_KEY_ID     = aws_iam_access_key.s3.id
    AWS_SECRET_ACCESS_KEY = aws_iam_access_key.s3.secret
  }
}
