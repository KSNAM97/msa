# =============================================================================
# [monitoring.tf] CloudWatch 알람 + 대시보드 (샌드박스: 비용이 거의 들지 않는 최소 구성)
#   - 알람 3종(RDS CPU / 여유 스토리지 / 노드 CPU): 임계치를 넘으면 SNS 로 이메일 전송
#   - 대시보드 1개(무료 한도 3개 이내): RDS 와 노드 지표를 한 화면에서 확인
#   - EKS 컨트롤 플레인 로그는 eks.tf 에서 설정(보관 3일)
#   알림을 받으려면 먼저 terraform/notify 스택을 apply 해서 SNS 토픽/이메일 구독이 있어야 한다.
# =============================================================================

locals {
  # notify 스택이 만든 토픽(nam97-aws-resource-alerts). 메인 인프라를 destroy 해도 이 토픽은 유지된다
  alarm_topic_arn = "arn:aws:sns:${var.region}:${data.aws_caller_identity.me.account_id}:nam97-aws-resource-alerts"
  node_asg_name   = module.eks.eks_managed_node_groups["default"].node_group_autoscaling_group_names[0]
}

# RDS CPU 사용률: 5분 평균이 80% 를 두 번 연속 넘으면 알림 (db.t4g.micro 는 버스트 크레딧 방식이라 지속 과부하 감지용)
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "nam97-rds-cpu-high"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.this.identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [local.alarm_topic_arn]
  treat_missing_data  = "notBreaching" # 지표가 없을 때(생성 직후 등) 오경보 방지
}

# RDS 여유 스토리지: 2GB 미만이면 알림 (20GB 고정 스토리지라 가득 차면 DB 가 멈춘다)
resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "nam97-rds-free-storage-low"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.this.identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2 * 1024 * 1024 * 1024 # 바이트 단위
  comparison_operator = "LessThanThreshold"
  alarm_actions       = [local.alarm_topic_arn]
  treat_missing_data  = "notBreaching"
}

# 노드(EC2) CPU: 노드 그룹 평균이 85% 를 10분(5분 x 2) 넘으면 알림. 오토스케일러가 못 따라가는 상황을 알려 준다
resource "aws_cloudwatch_metric_alarm" "node_cpu" {
  alarm_name          = "nam97-node-cpu-high"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { AutoScalingGroupName = local.node_asg_name }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [local.alarm_topic_arn]
  treat_missing_data  = "notBreaching"
}

# 대시보드: 관리자 페이지의 "CloudWatch 대시보드" 링크가 이 이름(nam97-sandbox)을 연다
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "nam97-sandbox"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "RDS CPU / 연결 수"
          region = var.region
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.this.identifier],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.this.identifier, { yAxis = "right" }]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title   = "RDS 여유 스토리지 (바이트)"
          region  = var.region
          view    = "timeSeries"
          metrics = [["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", aws_db_instance.this.identifier]]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title   = "노드 CPU 사용률 (노드 그룹 평균)"
          region  = var.region
          view    = "timeSeries"
          metrics = [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", local.node_asg_name]]
        }
      }
    ]
  })
}
