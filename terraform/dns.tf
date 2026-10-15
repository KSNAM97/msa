# =============================================================================
# [dns.tf] 서브도메인 -> ingress-nginx 로드밸런서(NLB) 연결
#   도메인(ksnam97.com)은 직접 호스팅 중인 기존 Route53 존이므로, 존/NS/기존 레코드는 건드리지 않고
#   CNAME 4개만 만들고 지운다. (도메인의 네임서버도 변경하지 않음)
# =============================================================================
locals {
  # repo ingress 기준 서브도메인 -> ingress-nginx 로드밸런서
  hosts = ["server", "argo", "prometheus", "grafana", "db"]
}

# 기존 호스팅 존 사용: 존의 NS/SOA/기존 레코드(A, www)는 건드리지 않고 CNAME 4개만 추가/삭제
data "aws_route53_zone" "existing" {
  name = var.domain
}

# ingress-nginx 가 만든 로드밸런서의 호스트명을 읽는다 (CNAME 의 값). apply 순서상 ingress 설치 후에 조회됨
data "kubernetes_service" "ingress" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
  depends_on = [helm_release.ingress_nginx]
}

# server/argo/prometheus/grafana.ksnam97.com -> 로드밸런서. TTL 60초: 로드밸런서가 바뀌어도 빠르게 반영
resource "aws_route53_record" "host" {
  for_each = toset(local.hosts)
  zone_id  = data.aws_route53_zone.existing.zone_id
  name     = "${each.key}.${var.domain}"
  type     = "CNAME"
  ttl      = 60
  records  = [data.kubernetes_service.ingress.status[0].load_balancer[0].ingress[0].hostname]
}
