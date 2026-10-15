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

# S3 게이트웨이 엔드포인트 (무료): 노드/파드에서 S3 로 가는 트래픽(상품 이미지 업로드 등)이 NAT 게이트웨이와 인터넷을 거치지 않고
# VPC 안의 전용 경로로 간다. -> NAT 데이터 처리 요금 절감 + 트래픽이 AWS 내부망에만 머무름.
# private 서브넷의 라우트 테이블에 "S3 로 가는 길"이 추가되는 방식이라 앱 코드/설정 변경은 필요 없다.
# (브라우저가 읽는 products/ 이미지의 공개 읽기 정책은 그대로: 사용자는 인터넷으로 S3 에 직접 접속한다)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
  tags              = { Name = "${var.cluster_name}-s3" }
}
