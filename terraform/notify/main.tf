# =============================================================================
# [notify/main.tf] AWS 리소스 생성/삭제 알림 (SNS 이메일)
#
# 동작: AWS 에서 중요한 리소스가 만들어지거나 지워지면(CloudTrail 관리 이벤트)
#       EventBridge 규칙이 감지 -> 읽기 쉬운 문장으로 바꿔 -> SNS 토픽 -> 이메일 발송
#
# ★ 메인 인프라(../)와 "별도 스택"(별도 state)으로 둔 이유:
#   메인 인프라를 destroy 할 때 알림 장치도 같이 사라지면 "삭제됨" 알림을 받을 수 없다.
#   이 스택은 한 번만 apply 하고 계속 유지한다. (비용: SNS/EventBridge 는 이 사용량에서 사실상 무료)
#
# 사용:  cd terraform/notify
#        terraform init
#        terraform apply -var notify_email=받을@이메일주소
#        -> 이메일로 오는 "AWS Notification - Subscription Confirmation" 의 Confirm subscription 링크를 눌러야 알림이 시작된다
# =============================================================================
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

variable "region" { default = "ap-northeast-2" } # 메인 인프라와 같은 리전의 이벤트만 감지한다
variable "notify_email" { type = string }        # 알림 받을 이메일 (기본값 없음: apply 때 직접 지정)

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "nam97-mall", Environment = "sandbox", ManagedBy = "terraform" }
  }
}

# 알림을 감지할 이벤트 이름. 너무 많으면 메일이 쏟아지므로 "비용이 큰/핵심 리소스"의 생성과 삭제만 고른다
locals {
  watched_events = [
    "CreateCluster", "DeleteCluster", "CreateNodegroup", "DeleteNodegroup", # EKS (제어면 + 노드)
    "CreateDBInstance", "DeleteDBInstance",                                 # RDS
    "CreateVpc", "DeleteVpc",                                               # VPC
    "CreateNatGateway", "DeleteNatGateway",                                 # NAT (시간당 과금)
    "CreateLoadBalancer", "DeleteLoadBalancer",                             # NLB (ingress-nginx 가 생성)
    "CreateRepository", "DeleteRepository",                                 # ECR
    "CreateBucket", "DeleteBucket",                                         # S3
  ]
}

# ---------- SNS 토픽 + 이메일 구독 ----------
resource "aws_sns_topic" "alerts" {
  name = "nam97-aws-resource-alerts"
}

# 이메일 구독: apply 직후에는 "대기 중(PendingConfirmation)" 상태이고, 메일의 확인 링크를 눌러야 활성화된다
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notify_email
}

# ---------- EventBridge 규칙: 위 이벤트가 "성공"했을 때만 감지 ----------
resource "aws_cloudwatch_event_rule" "resource_changes" {
  name        = "nam97-resource-create-delete"
  description = "EKS/RDS/VPC/NAT/NLB/ECR/S3 생성-삭제 감지"
  event_pattern = jsonencode({
    "detail-type" = ["AWS API Call via CloudTrail"]
    source        = ["aws.eks", "aws.rds", "aws.ec2", "aws.elasticloadbalancing", "aws.ecr", "aws.s3"]
    detail = {
      eventName = local.watched_events
      errorCode = [{ exists = false }] # 권한 오류 등으로 "실패한" 호출은 제외
    }
  })
}

resource "aws_cloudwatch_event_target" "to_sns" {
  rule = aws_cloudwatch_event_rule.resource_changes.name
  arn  = aws_sns_topic.alerts.arn

  # 원본 JSON 대신 읽기 쉬운 한 줄 메시지로 변환해서 보낸다
  input_transformer {
    input_paths = {
      event  = "$.detail.eventName"
      src    = "$.detail.eventSource"
      who    = "$.detail.userIdentity.arn"
      time   = "$.detail.eventTime"
      region = "$.detail.awsRegion"
    }
    input_template = "\"[AWS 리소스 알림] <event> (<src>) / 실행자: <who> / 리전: <region> / 시각(UTC): <time>\""
  }
}

# 이 EventBridge 규칙만 토픽에 발행할 수 있도록 제한 (confused deputy 방지: aws:SourceArn 조건)
resource "aws_sns_topic_policy" "allow_events" {
  arn = aws_sns_topic.alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgePublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.alerts.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.resource_changes.arn } }
    }]
  })
}

output "topic_arn" { value = aws_sns_topic.alerts.arn }
output "next_step" { value = "이메일로 온 'Subscription Confirmation' 메일의 Confirm subscription 링크를 눌러야 알림이 시작됩니다." }
