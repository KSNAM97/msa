# destroy 후 남은 리소스 확인 (읽기 전용: 조회만 하고 아무것도 만들거나 지우지 않는다). 사용: .\verify-destroy.ps1
# 항목마다 [OK]=없음 / [남음]=남아있음(과금될 수 있음). Route53 존은 기존 존이라 "남음"으로 나오는 게 정상.
param([string]$Region = 'ap-northeast-2', [string]$Cluster = 'my-cluster', [string]$Domain = 'ksnam97.com')
$left = 0
# 조회 결과가 비어 있으면 OK, 값이 있으면 남은 리소스로 보고 개수를 센다
function Check($name, $out) {
  $out = ($out | Out-String).Trim()
  if ($out -and $out -ne 'None' -and $out -ne '[]') { Write-Host "[남음] $name`n$out" -ForegroundColor Red; $script:left++ }
  else { Write-Host "[OK]   $name" -ForegroundColor Green }
}
$acct = aws sts get-caller-identity --query Account --output text

Check 'EKS 클러스터'       (aws eks list-clusters --region $Region --query "clusters[?@=='$Cluster']" --output text)
Check 'RDS'                (aws rds describe-db-instances --region $Region --query "DBInstances[?starts_with(DBInstanceIdentifier,'$Cluster')].DBInstanceIdentifier" --output text)
Check 'ECR 레포'           (aws ecr describe-repositories --region $Region --query "repositories[?contains(['apigateway','member-service','product-service','ordering-service','frontend-service'],repositoryName)].repositoryName" --output text)
Check 'S3 버킷'            (aws s3api list-buckets --query "Buckets[?starts_with(Name,'ksnam97-frontend-image-$acct')].Name" --output text)
Check 'IAM 사용자'         (aws iam list-users --query "Users[?starts_with(UserName,'$Cluster')].UserName" --output text)
Check 'IAM 역할'           (aws iam list-roles --query "Roles[?starts_with(RoleName,'$Cluster')].RoleName" --output text)
Check 'VPC'                (aws ec2 describe-vpcs --region $Region --filters "Name=tag:Name,Values=$Cluster-vpc" --query 'Vpcs[].VpcId' --output text)
Check 'NAT 게이트웨이'     (aws ec2 describe-nat-gateways --region $Region --filter "Name=state,Values=available,pending" --query "NatGateways[?Tags[?Value=='$Cluster-vpc']].NatGatewayId" --output text)
# 로드밸런서 점검: ingress-nginx 가 만든 로드밸런서는 이름이 임의의 16진수(예: ab57dc52...)라서 이름으로 거를 수 없다.
# 이 계정은 이 프로젝트 전용이므로 "리전에 로드밸런서가 하나라도 남아 있으면" 잔여로 본다. (과금 대상이고 VPC 삭제도 막는다)
#   - ALB/NLB (elbv2)  - 클래식 ELB(과거 방식 잔여 확인용)  - 타깃 그룹  - k8s 가 만든 보안그룹(k8s-elb-*)  - 로드밸런서 네트워크 인터페이스(ENI)
Check '로드밸런서 ALB/NLB'  (aws elbv2 describe-load-balancers --region $Region --query "LoadBalancers[].LoadBalancerName" --output text)
Check '로드밸런서 클래식'   (aws elb describe-load-balancers --region $Region --query "LoadBalancerDescriptions[].LoadBalancerName" --output text)
Check '타깃 그룹'          (aws elbv2 describe-target-groups --region $Region --query "TargetGroups[].TargetGroupName" --output text)
Check 'k8s 보안그룹(ELB)'  (aws ec2 describe-security-groups --region $Region --filters "Name=group-name,Values=k8s-elb-*" --query "SecurityGroups[].GroupId" --output text)
Check 'ELB 네트워크 ENI'   (aws ec2 describe-network-interfaces --region $Region --filters "Name=description,Values=ELB*" --query "NetworkInterfaces[].NetworkInterfaceId" --output text)
Check '미연결 EIP'         (aws ec2 describe-addresses --region $Region --query 'Addresses[?AssociationId==null].PublicIp' --output text)
Check 'EBS 볼륨(k8s PVC)'  (aws ec2 describe-volumes --region $Region --filters "Name=tag-key,Values=kubernetes.io/created-for/pvc/name" --query 'Volumes[].VolumeId' --output text)
Check 'Route53 호스팅 존'  (aws route53 list-hosted-zones-by-name --dns-name $Domain --query "HostedZones[?Name=='$Domain.'].Id" --output text)
Check 'CloudWatch 로그'    (aws logs describe-log-groups --region $Region --log-group-name-prefix "/aws/eks/$Cluster" --query 'logGroups[].logGroupName' --output text)

if ($left) { "`n남은 항목 $left 개 - 위 출력을 알려주세요." } else { "`n전부 삭제됨." }
