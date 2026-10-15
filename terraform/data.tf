# ECR, S3, RDS, IAM 키, 앱 시크릿

locals {
  apps = ["apigateway", "member-service", "product-service", "ordering-service", "frontend-service"]
}

# ---------- ECR ----------
resource "aws_ecr_repository" "app" {
  for_each     = toset(local.apps)
  name         = each.key
  force_delete = true
  # 보안: push 할 때마다 알려진 취약점(CVE)을 자동 스캔하고, 이미지는 저장 시 암호화한다
  # (태그는 CI 가 latest 하나로 덮어쓰므로 immutable 로는 바꾸지 않는다)
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
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

# 보안: 저장 시 암호화(SSE-S3). 기본값이지만 코드로 명시해 점검 도구/리뷰에서 확인되게 한다
resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_policy" "images_public_read" {
  bucket = aws_s3_bucket.images.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadProductImages"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"                           # 읽기만 허용 (최소 권한)
        Resource  = "${aws_s3_bucket.images.arn}/products/*" # product-service 가 올리는 경로(products/)로 한정
      },
      {
        # 보안: HTTP(암호화 없음) 요청은 모두 거부 -> HTTPS 로만 접근 가능
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.images.arn, "${aws_s3_bucket.images.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
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

# 샌드박스(비용 최소화) 프로파일: 가장 작은 인스턴스 + 단일 AZ + 최소 스토리지 + 백업/모니터링 부가기능 끔.
# - db.t4g.micro: Graviton(ARM) 최소 사양. 신규 계정의 RDS 프리티어(750시간/월)와 같은 급
# - multi_az=false: 대기(standby) 인스턴스가 없어 비용이 절반. 대신 AZ 장애 시 중단됨(학습용이라 허용)
# - backup_retention_period=0: 자동 백업 끔(스냅샷 비용 없음). 데이터 복구 불가 -> 운영에서는 7 이상
# - performance_insights/모니터링 끔: 추가 요금 방지
# 비용의 대부분은 RDS 가 아니라 EKS 제어면/NAT/노드이므로, 안 쓸 때는 destroy 하는 것이 가장 큰 절감이다.
resource "aws_db_instance" "this" {
  identifier        = "${var.cluster_name}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp2" # 최소 20GB 에서 가장 저렴한 범용 SSD
  multi_az          = false

  backup_retention_period      = 0
  performance_insights_enabled = false
  monitoring_interval          = 0
  auto_minor_version_upgrade   = true
  apply_immediately            = true
  db_name                      = "ordermsa" # 서비스들이 공유하는 DB 이름 (application-prod.yml 의 URL 과 일치)
  username                     = "admin"
  password                     = random_password.db.result
  db_subnet_group_name         = aws_db_subnet_group.this.name
  vpc_security_group_ids       = [aws_security_group.rds.id]
  # 학습/개발용 설정: destroy 시 최종 스냅샷 없이 바로 삭제. 운영에서는 true/false 를 반대로 바꿀 것
  skip_final_snapshot = true
  deletion_protection = false
  publicly_accessible = false
  # 보안: 디스크(저장 데이터)와 스냅샷을 암호화한다 (생성 시점에만 설정 가능 -> 기존 DB 는 교체됨)
  storage_encrypted     = true
  copy_tags_to_snapshot = true
}

# ---------- k8s 네임스페이스 / 시크릿 (manifest의 secretKeyRef) ----------
resource "kubernetes_namespace" "ksnam97" {
  metadata { name = "ksnam97" }
  depends_on = [module.eks]
}

resource "kubernetes_secret" "app" {
  metadata {
    name      = "my-app-secrets"
    namespace = kubernetes_namespace.ksnam97.metadata[0].name
  }
  data = {
    DB_HOST = aws_db_instance.this.address
    DB_PW   = random_password.db.result
    # 주문 알림을 보낼 SNS 토픽 (order_alerts.tf). ordering 서비스가 SNS_TOPIC_ARN 환경변수로 읽는다
    SNS_TOPIC_ARN = data.aws_sns_topic.alerts.arn
  }
}

resource "kubernetes_secret" "aws" {
  metadata {
    name      = "aws-secret"
    namespace = kubernetes_namespace.ksnam97.metadata[0].name
  }
  data = {
    AWS_ACCESS_KEY_ID     = aws_iam_access_key.s3.id
    AWS_SECRET_ACCESS_KEY = aws_iam_access_key.s3.secret
  }
}

# ---------- 소스에서 분리한 비밀 값 (JWT 서명 키 / 초기 관리자 비밀번호) ----------
# 예전에는 application-prod.yml 과 InitialDataLoader 에 고정값이 들어 있었다(공개 저장소에 노출).
# 이제 apply 때마다 랜덤으로 생성해 쿠버네티스 시크릿으로만 전달한다. 값은 이 폴더의 terraform state(git 제외)에만 있다.

# HS512 서명에는 64바이트 이상의 키가 필요 -> 랜덤 64바이트를 Base64 로 인코딩 (앱이 Base64 디코딩해서 사용)
resource "random_id" "jwt_access" { byte_length = 64 }
resource "random_id" "jwt_refresh" { byte_length = 64 }

# 초기 관리자(admin) 비밀번호. 특수문자는 로그인/쉘에서 다루기 번거로워 제외
resource "random_password" "admin" {
  length  = 20
  special = false
}

# apigateway(검증)와 member(서명)가 같은 키를 써야 하므로 시크릿 하나를 공유한다
resource "kubernetes_secret" "jwt" {
  metadata {
    name      = "jwt-secret"
    namespace = kubernetes_namespace.ksnam97.metadata[0].name
  }
  data = {
    JWT_SECRET_KEY    = random_id.jwt_access.b64_std
    JWT_SECRET_KEY_RT = random_id.jwt_refresh.b64_std
  }
}

# member 서비스가 최초 기동 시 admin 계정을 만들 때 사용
resource "kubernetes_secret" "admin" {
  metadata {
    name      = "admin-secret"
    namespace = kubernetes_namespace.ksnam97.metadata[0].name
  }
  data = {
    ADMIN_PASSWORD = random_password.admin.result
  }
}

# ---------- Grafana 관리자 비밀번호 ----------
# Grafana 이미지의 기본 계정은 admin/admin 이라 공개 주소에 그대로 두면 위험하다.
# 랜덤 비밀번호를 만들어 시크릿(grafana-secret)으로 전달하고, 파드는 환경변수 GF_SECURITY_ADMIN_* 로 읽는다
# (repo 의 msa/k8s/k8s-monitoring/grafana-depl_svc.yml 참고). 확인: terraform output -raw grafana_password
resource "random_password" "grafana" {
  length  = 20
  special = false
}

# monitoring 네임스페이스: 원래는 ArgoCD 가 만들지만, 파드가 뜨기 전에 시크릿이 있어야 하므로 테라폼이 먼저 만든다
# (ArgoCD 의 CreateNamespace=true 는 이미 있어도 문제없이 동작)
resource "kubernetes_namespace" "monitoring" {
  metadata { name = "monitoring" }
  depends_on = [module.eks]
}

resource "kubernetes_secret" "grafana" {
  metadata {
    name      = "grafana-secret"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  data = {
    GF_SECURITY_ADMIN_USER     = "admin"
    GF_SECURITY_ADMIN_PASSWORD = random_password.grafana.result
    SNS_TOPIC_ARN              = data.aws_sns_topic.alerts.arn # Grafana 알람 연락처(SNS) 토픽. grafana-alerting.yml 이 $__env{SNS_TOPIC_ARN} 로 읽는다
  }
}

# ---------- DB 관리 화면(Adminer, repo 의 msa/k8s/k8s-monitoring/adminer.yml)용 비밀 값 ----------
# 접속 인증(Basic)용 비밀번호: 이 비밀번호를 알아야 db.<도메인> 화면이 열린다. (DB 자체 비밀번호와는 별개의 1차 방어)
resource "random_password" "adminer" {
  length  = 20
  special = false
}

# ingress-nginx Basic 인증은 htpasswd 형식("아이디:bcrypt해시")을 auth 키에서 읽는다.
# bcrypt() 는 호출할 때마다 해시가 달라지므로, 매번 변경으로 인식하지 않도록 data 변경은 무시한다(비밀번호가 바뀌면 resource 를 교체)
resource "kubernetes_secret" "adminer_auth" {
  metadata {
    name      = "adminer-basic-auth"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  data = {
    auth = "admin:${bcrypt(random_password.adminer.result)}"
  }
  lifecycle {
    ignore_changes = [data]
  }
}

# Adminer 로그인 화면의 "서버" 칸에 미리 채울 RDS 주소
resource "kubernetes_secret" "adminer_config" {
  metadata {
    name      = "adminer-config"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  data = {
    ADMINER_DEFAULT_SERVER = aws_db_instance.this.address
  }
}
