# NAM97 MALL

AWS EKS 위에서 운영되는 **마이크로서비스(MSA) 쇼핑몰**입니다.
애플리케이션 개발부터 **인프라 자동 구축(Terraform)**, **CI/CD(GitHub Actions + ArgoCD)**, **모니터링**, **비용·삭제 알림**까지 한 프로젝트로 구현했습니다.

> 이 저장소는 포트폴리오용 공개 프로젝트입니다. 인프라는 필요할 때만 띄우고(`terraform apply`) 쓰지 않을 때는 모두 삭제(`terraform destroy`)하는 샌드박스 방식으로 운영합니다.

## 문서

| 문서 | 내용 |
|---|---|
| [실행 방법](docs/RUNBOOK.md) | 만들기 · 확인 · 배포 · 삭제 순서, 문제 해결 (처음 보는 분은 여기부터) |
| [구조와 폴더 경로](docs/STRUCTURE.md) | 어디에 무엇이 있는지 (폴더 트리, 서비스별 소스, 주소 구성) |
| [함수/API 참고](docs/REFERENCE.md) | API 목록과 권한, 서비스 메서드, 프론트 함수, 테라폼 변수, 스크립트 |
| [구성과 주요 스택](docs/ARCHITECTURE.md) | 전체 구성도, 서비스/API, 기술 스택, Terraform 구성, 배포 흐름, 보안 설계 |
| [디자인 가이드](docs/DESIGN.md) | 디자인 원칙, 스타일 토큰, 레이아웃, 페이지 구성, 사용자 흐름, 입력 규칙, 관리자/Grafana 화면 |
| 샘플 화면 | [쇼핑몰](docs/samples/storefront.html) · [관리자](docs/samples/admin-console.html) · [Grafana 대시보드](docs/samples/grafana-dashboards.html) — 내려받아 브라우저로 열면 서버 없이 화면을 볼 수 있습니다 |

## 한눈에 보기

| 영역 | 내용 |
|---|---|
| 서비스 | API Gateway, Member(회원/로그인), Product(상품), Ordering(주문), Frontend(정적 웹) |
| 인프라 | VPC, EKS(관리형 노드 그룹), RDS MySQL, S3, ECR, Route53 |
| 배포 | GitHub Actions(이미지 빌드/푸시) + ArgoCD(GitOps 배포) |
| 트래픽/보안 | ingress-nginx, cert-manager(Let's Encrypt HTTPS), JWT 인증 |
| 운영 | HPA + Cluster Autoscaler, Prometheus + Grafana, SNS 생성·삭제 알림 |
| 코드로 관리 | 인프라 전체를 Terraform 한 번의 `apply`로 구축 |

## 아키텍처

```mermaid
flowchart LR
  user([사용자]) -->|HTTPS| dns[Route53]
  dns --> nlb[NLB]
  nlb --> ingress[ingress-nginx<br/>+ cert-manager]
  subgraph EKS[EKS 클러스터]
    ingress -->|/| fe[Frontend<br/>nginx 정적 웹]
    ingress -->|/member-service<br/>/product-service<br/>/ordering-service| gw[API Gateway<br/>JWT 검증]
    gw --> member[Member]
    gw --> product[Product]
    gw --> ordering[Ordering]
    ordering -->|OpenFeign| product
    argocd[ArgoCD] -.배포.-> EKS
    prom[Prometheus/Grafana] -.수집.-> EKS
  end
  member --> rds[(RDS MySQL)]
  product --> rds
  ordering --> rds
  product -->|이미지 업로드| s3[(S3)]
  gh[GitHub Actions] -->|이미지 push| ecr[ECR]
  gh -.매니페스트 변경.-> argocd
```

- **API Gateway**가 모든 API 요청의 JWT를 검증하고, 사용자 ID/권한을 헤더(`X-User-Id`, `X-User-Role`)로 내부 서비스에 전달합니다.
- **Ordering → Product**는 쿠버네티스 Service DNS를 OpenFeign으로 호출해 재고를 확인/차감합니다.
- 회원가입·로그인 등 일부 경로만 공개이고, 나머지는 토큰이 필요합니다.

## 기술 스택

- **Backend**: Java 17, Spring Boot 3.4, Spring Cloud Gateway, OpenFeign, Spring Data JPA, JWT(jjwt)
- **Frontend**: HTML/CSS/순수 JavaScript, nginx (프레임워크 없는 미니멀 스토어프런트)
- **Infra**: AWS(EKS, RDS, S3, ECR, Route53, SNS, EventBridge), Terraform
- **Kubernetes**: ingress-nginx, cert-manager, ArgoCD, HPA, Cluster Autoscaler, metrics-server, Prometheus, Grafana
- **CI/CD**: GitHub Actions, ArgoCD(GitOps)

## 주요 기능

- 회원가입 / 로그인(JWT) / 로그아웃
- 상품 목록(카테고리 메뉴, 검색, 정렬) · 상세 · 장바구니 · 주문 · 주문내역
- 관리자: 상품 등록(이미지 S3 업로드) / 삭제 (서버에서 `ADMIN` 권한 검사)
- 중복 제출 방지, 반응형 UI, XSS 방지(출력 이스케이프)

## 저장소 구조

```
.
├── msa/
│   ├── apigateway/  member/  product/  ordering/   # Spring Boot 서비스
│   ├── frontend/                                   # 정적 웹(nginx)
│   └── k8s/                                        # ingress, HPA, 모니터링, autoscaler 매니페스트
├── argocd/                                         # ArgoCD App of Apps (root-app + apps)
├── terraform/                                      # 인프라 코드 (VPC/EKS/RDS/S3/ECR/애드온/DNS)
│   └── notify/                                     # 생성·삭제 SNS 알림 (별도 스택)
└── .github/workflows/                              # CI: 이미지 빌드/푸시 + 배포
```

## 배포 흐름 (CI/CD)

1. 코드를 `main`에 push
2. GitHub Actions가 **변경된 서비스만** 도커 이미지로 빌드해 ECR에 push하고 롤아웃
3. ArgoCD가 `argocd/apps`의 매니페스트를 감시하며 클러스터 상태를 Git과 자동 동기화 (prune + self-heal)

## 인프라 구축 (Terraform)

한 번의 `apply`로 다음이 순서대로 만들어집니다.

`VPC → EKS → RDS/S3/ECR → ingress-nginx · cert-manager · ArgoCD · autoscaler → DNS → 앱 배포 → CI 실행`

```bash
cd terraform
terraform init
terraform apply
```

- state 저장소: 최초 1회 `terraform/bootstrap`을 apply해 S3 버킷을 만든 뒤 메인(`terraform/`)을 init합니다. 버킷은 메인을 destroy해도 유지됩니다.
- 필요 도구: Terraform ≥ 1.10, AWS CLI, kubectl, gh CLI(GitHub Actions 자동 실행용)
- 비용 절감: RDS는 가장 작은 샌드박스 사양, 모든 리소스에 `Environment=sandbox` 태그
- 삭제: `terraform destroy` (ArgoCD가 만든 리소스/로드밸런서까지 정리하도록 destroy 훅 포함)
- HTTPS 인증서는 destroy 시 백업하고 다음 apply에서 복원해 Let's Encrypt 발급 한도를 피합니다.

### 접속 주소와 관리자 계정 확인

쇼핑몰 `admin`, Grafana, ArgoCD의 비밀번호는 소스에 없고 apply 때마다 랜덤으로 만들어집니다. apply가 끝난 뒤 아래 스크립트 하나로 주소와 계정을 모두 확인합니다.

```powershell
cd terraform
.\show-credentials.ps1
```

| 서비스 | 주소 | 비밀번호 확인 명령 (모두 아이디 `admin`) |
|---|---|---|
| 쇼핑몰 관리자 | `https://server.<도메인>/login.html` | `.\show-credentials.ps1 -Only admin` |
| Grafana | `https://grafana.<도메인>` | `.\show-credentials.ps1 -Only grafana` |
| ArgoCD | `https://argo.<도메인>` | `.\show-credentials.ps1 -Only argocd` |
| Prometheus | `https://prometheus.<도메인>` | 로그인 없음 (아래 한계 참고) |

`terraform apply`가 끝나면 이 정보가 리포 루트의 `password.txt`에 **자동으로 저장**됩니다(`credentials.tf`). 이 파일은 `.gitignore`로 git에서 제외되어 내 PC에만 남습니다. 수동으로 다시 저장하려면 `.\show-credentials.ps1 -Save`를 실행합니다.

스크립트 없이 직접 확인하려면 다음과 같습니다.

```powershell
terraform output -raw admin_password       # 쇼핑몰 관리자
terraform output -raw grafana_password     # Grafana
# ArgoCD (클러스터 시크릿을 디코딩)
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}')))
```

쇼핑몰에 `admin`으로 로그인하면 계정 메뉴의 **관리자** 페이지에서 서비스 상태를 보고 Grafana/Prometheus/ArgoCD/CloudWatch로 이동할 수 있습니다.

### 생성·삭제 알림 (선택)

```bash
cd terraform/notify
terraform init
terraform apply -var notify_email=you@example.com
```

EKS/RDS/VPC/NAT/로드밸런서/ECR/S3의 생성·삭제가 CloudTrail → EventBridge → SNS 이메일로 전달됩니다.
메인 인프라를 지워도 알림이 사라지지 않도록 별도 스택으로 분리했습니다.

## 설계 포인트

- **GitOps**: 클러스터 상태의 기준은 Git. 수동 `kubectl apply` 없이 ArgoCD가 반영
- **최소 권한**: CI용 IAM 사용자는 EKS `soldesk` 네임스페이스 편집 권한만 부여, S3 이미지는 `products/` 읽기만 공개
- **비밀 정보 분리**: DB 비밀번호, JWT 서명 키, 초기 관리자 비밀번호를 소스에 두지 않고 Terraform이 랜덤 생성해 쿠버네티스 시크릿(`my-app-secrets`, `jwt-secret`, `admin-secret`)으로만 전달합니다. 앱은 환경변수로 읽습니다.
- **재현 가능한 인프라**: 클러스터 생성부터 DNS·HTTPS·앱 배포까지 코드로 재현, 삭제 후 잔여 리소스 점검 스크립트(`terraform/verify-destroy.ps1`) 제공
- **트러블슈팅 경험**: 노드 간 보안그룹 규칙으로 인한 504, Cluster Autoscaler 버전 불일치, Let's Encrypt 발급 한도 등을 진단해 코드에 반영

## 알려진 한계 / 개선 예정

- 탈퇴한 회원의 로그인 토큰은 만료 시각까지 유효합니다(JWT가 서버 상태를 저장하지 않는 방식). 블랙리스트나 토큰 짧은 만료 + 리프레시로 보완할 수 있습니다.
- 주문 취소는 서비스 간 분산 트랜잭션이 아니어서 극단적인 장애 시 재고 불일치 가능성이 있습니다(사가/아웃박스 패턴으로 개선 가능).
- Prometheus는 로그인 없이 공개되어 있습니다(Ingress Basic 인증 또는 IP 제한 필요)
- Terraform state에는 비밀 값(DB 비밀번호, JWT 키 등)이 들어 있어 S3 원격 backend(암호화, 버전 관리, 공개 차단, HTTPS 전용, 네이티브 잠금)에 저장합니다. 다만 단일 AWS 계정/단일 사용자 기준이며, 팀 운영 시에는 접근 권한(IAM) 분리와 KMS 키 암호화를 추가하는 것이 좋습니다.
- 단일 NAT·단일 AZ RDS·자동 백업 off 등 비용 최소화(샌드박스) 설정

## 스크린샷

> 배포 후 `docs/images/`에 화면 캡처를 추가하고 아래에 연결하세요.

<!-- ![메인](docs/images/main.png) -->
<!-- ![상품 상세](docs/images/detail.png) -->
<!-- ![ArgoCD](docs/images/argocd.png) -->

## 라이선스

[MIT License](LICENSE) 로 공개합니다. 개인 학습/포트폴리오 목적의 프로젝트이며, 자유롭게 참고하고 수정할 수 있습니다.
