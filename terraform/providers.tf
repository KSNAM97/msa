# =============================================================================
# [providers.tf] 사용할 프로바이더와 버전.
#   helm/kubernetes 프로바이더는 EKS 가 만들어진 뒤의 접속 정보(module.eks 출력)로 설정된다.
#   -> 한 번의 apply 로 "클러스터 생성 + 그 안에 설치"까지 이어지는 이유
# =============================================================================
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    helm       = { source = "hashicorp/helm", version = "~> 2.12" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.27" }
    random     = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" { region = var.region }

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
