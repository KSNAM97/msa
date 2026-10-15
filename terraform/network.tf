# =============================================================================
# [network.tf] VPC: EKS 노드/RDS 가 들어가는 네트워크
#   public 서브넷  : 인터넷 게이트웨이 연결. ingress-nginx 의 외부 로드밸런서(클래식 ELB)가 여기에 생성됨
#   private 서브넷 : EKS 노드, RDS. 인터넷으로 나갈 때만 NAT 를 거침 (외부에서 직접 접근 불가)
# =============================================================================
data "aws_availability_zones" "this" { state = "available" }

locals {
  # 가용영역 2개 사용 (노드/RDS 서브넷 그룹이 최소 2개 AZ 를 요구)
  azs = slice(data.aws_availability_zones.this.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name            = "${var.cluster_name}-vpc"
  cidr            = "10.0.0.0/16"
  azs             = local.azs
  public_subnets  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true # ponytail: 단일 NAT(비용절감), 운영은 AZ별 NAT

  # 이 태그가 있어야 k8s(AWS LB 컨트롤러/in-tree)가 로드밸런서를 올릴 서브넷을 찾는다
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}
