# =============================================================================
# [order_alerts.tf] 주문/재고 알림: ordering 서비스가 SNS 토픽에 메시지를 발행 -> 이메일
#   - 토픽은 notify 스택(terraform/notify)이 만든 "nam97-aws-resource-alerts" 를 그대로 쓴다.
#     (그 스택은 destroy 때 같이 지워지지 않고 이메일 구독 확인도 유지되므로, 이 인프라를 만들고 지울 때마다 구독을 다시 확인할 필요가 없다)
#     -> notify 스택을 먼저 apply 해 두어야 한다. 없으면 plan 에서 토픽을 찾지 못한다는 오류가 난다.
#   - 같은 토픽에 Grafana 알람(monitoring.tf/grafana_irsa)도 발행한다. 아래 정책을 두 역할이 함께 쓴다
#   - 인증은 키 저장 없이 IRSA(서비스어카운트에 연결한 IAM 역할)로 한다. 권한은 "이 토픽에 Publish 만" 허용 (최소 권한)
# =============================================================================
data "aws_sns_topic" "alerts" {
  name = "nam97-aws-resource-alerts"
}

resource "aws_iam_policy" "order_alerts" {
  name        = "${var.cluster_name}-sns-publish-alerts"
  description = "publish alerts to one SNS topic (used by ordering service and grafana)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sns:Publish"]
      Resource = data.aws_sns_topic.alerts.arn
    }]
  })
}

module "ordering_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name        = "${var.cluster_name}-ordering-sns"
  role_policy_arns = { publish = aws_iam_policy.order_alerts.arn }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["ksnam97:ordering"] # 이 서비스어카운트만 역할을 맡을 수 있다
    }
  }
}

# 역할 ARN(계정 ID 포함)을 repo 매니페스트에 적지 않으려고 테라폼이 서비스어카운트를 직접 만든다 (ordering 매니페스트는 serviceAccountName: ordering)
resource "kubernetes_service_account" "ordering" {
  metadata {
    name      = "ordering"
    namespace = kubernetes_namespace.ksnam97.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = module.ordering_irsa.iam_role_arn
    }
  }
}
