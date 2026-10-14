# =============================================================================
# [eks.tf] EKS 클러스터 + 관리형 노드 그룹 + cluster-autoscaler 용 IAM 역할(IRSA)
# =============================================================================
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.k8s_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # 노드는 private 서브넷에만 배치

  # ponytail: API 서버 공개 엔드포인트. 운영에서는 접근 허용 CIDR 을 제한하거나 private 로 전환
  cluster_endpoint_public_access = true
  # terraform 을 실행한 IAM 주체(admin)에게 클러스터 관리자 권한 부여 (helm/kubernetes provider 가 이 권한으로 동작)
  enable_cluster_creator_admin_permissions = true

  # GitHub Actions(CI)용 IAM 사용자에게 클러스터 접근 권한 부여
  access_entries = {
    ci = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:user/${var.ci_user}"
      policy_associations = {
        # 최소 권한: CI는 soldesk 네임스페이스의 apply/rollout restart 만 필요
        edit = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
          access_scope = { type = "namespace", namespaces = ["soldesk"] }
        }
      }
    }
  }

  # 모듈 기본 규칙은 노드 간 1025-65535 만 허용 -> 다른 노드의 80포트(frontend) 접근이 막혀 504 발생
  node_security_group_additional_rules = {
    ingress_self_80 = {
      description = "Node to node HTTP 80 (ingress to frontend)"
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      type        = "ingress"
      self        = true
    }
    # NLB가 ingress 파드가 없는 노드로 보내면 노드 간 443 으로 전달됨
    ingress_self_443 = {
      description = "Node to node HTTPS 443 (NLB to ingress)"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      self        = true
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      # min/max 범위 안에서 cluster-autoscaler(addons.tf)가 Pending 파드를 보고 노드를 늘리고 줄인다
      min_size     = 2
      max_size     = 4
      desired_size = 2
    }
  }
}

# cluster-autoscaler 파드가 AWS(Auto Scaling) API 를 호출할 권한. 정적 키 대신 IRSA(서비스어카운트-IAM 연결) 사용.
# 신뢰 정책은 kube-system:cluster-autoscaler 서비스어카운트로만 한정되고, 권한은 이 클러스터의 태그가 붙은 ASG 로 한정됨
module "autoscaler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                        = "${var.cluster_name}-autoscaler"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }
}
