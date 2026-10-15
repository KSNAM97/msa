# 구조와 폴더 경로

> 무엇이 어디에 있는지 찾기 위한 문서입니다. 함수/API 설명은 [REFERENCE.md](REFERENCE.md), 실행 방법은 [RUNBOOK.md](RUNBOOK.md)를 보세요.

## 1. 전체 폴더 구조

```
aws-msa-backend/                       ← 저장소 루트 (GitHub: KSNAM97/msa)
├── README.md · LICENSE (MIT)
├── password.txt                       ← 접속 비밀번호 모음 (apply 때 자동 생성, git 제외)
├── .github/workflows/
│   └── deploy_ordermsa_with_k8s.yml   ← CI: 이미지 빌드 → ECR push → 롤아웃
├── argocd/                            ← CD: ArgoCD 가 읽는 앱 정의 (GitOps)
│   ├── root-app.yml                   ← 모든 앱의 부모(App of Apps)
│   └── apps/                          ← 앱별 정의 (member, product, ordering, apigateway, frontend, hpa, monitoring, services, argocd)
├── CHANGELOG.md                       ← 변경 이력
├── docs/                              ← 문서 (주제별 폴더)
│   ├── guide/                         ← RUNBOOK(실행) · STRUCTURE(구조) · REFERENCE(함수/API)
│   ├── design/                        ← ARCHITECTURE(구성) · DESIGN(화면 디자인)
│   ├── ops/                           ← TROUBLESHOOTING · ROLLBACK · RESULTS · SECURITY
│   ├── images/                        ← 구성도(architecture.svg)
│   └── samples/                       ← 화면 샘플(HTML, 서버 없이 열람, GitHub Pages)
├── msa/                               ← 애플리케이션과 쿠버네티스 매니페스트
│   ├── apigateway/ member/ product/ ordering/   ← Spring Boot 서비스 (각각 src, build.gradle, Dockerfile, k8s/)
│   ├── frontend/                      ← 정적 웹 (nginx)
│   └── k8s/                           ← 공용 매니페스트 (ingress, HPA, 모니터링, autoscaler)
└── terraform/                         ← 인프라 코드
    ├── *.tf                           ← 메인 스택
    ├── scripts/                       ← 운영 스크립트 (show-credentials · verify-destroy · sync-backend)
    ├── bootstrap/                     ← state 저장용 S3 버킷 (별도 스택)
    └── notify/                        ← 생성·삭제 SNS 알림 (별도 스택)
```

## 2. 서비스 폴더 (공통 구조)

`msa/<서비스>/` 는 모두 같은 모양입니다.

| 경로 | 내용 |
|---|---|
| `build.gradle`, `settings.gradle` | 빌드 설정 (Java 17, Spring Boot 3.4) |
| `Dockerfile` | 2단계 빌드(JDK에서 jar 생성 → JRE 이미지에 복사) |
| `k8s/depl_svc.yml` | Deployment(리소스, 환경변수, probe) + Service |
| `src/main/resources/application.yml` | 공통 설정, 지표 노출(`/actuator/prometheus`) |
| `src/main/resources/application-prod.yml` | 운영 설정 (DB 주소, 시크릿은 환경변수로 받음) |
| `src/main/java/com/example/ordersystem/` | 소스 (아래) |

### 서비스별 소스 (`src/main/java/com/example/ordersystem/`)

| 서비스 | 패키지/파일 | 역할 |
|---|---|---|
| apigateway | `JwtAuthFilter.java` | JWT 검증, `X-User-Id`/`X-User-Role` 주입, `/actuator` 차단 |
| member | `member/controller/MemberController.java` | 가입·로그인·내 정보·비밀번호·탈퇴·회원 목록 |
| | `member/controller/AdminDbController.java` | 관리자 DB 보기(읽기 전용) |
| | `member/controller/AdminMetricsController.java` | 관리자용 Prometheus 지표 조회(정해진 질의만) |
| | `member/service/MemberService.java` · `MemberValidator.java` | 회원 로직, 이메일/비밀번호 규칙 검사 |
| | `member/service/JwtTokenProvider.java` | 토큰 발급 |
| | `member/service/InitialDataLoader.java` | 최초 기동 시 `admin` 계정 생성(비밀번호는 환경변수) |
| | `member/domain`, `member/dto`, `member/repository` | 엔티티, 요청/응답 DTO, JPA 저장소 |
| product | `product/controller/ProductController.java` | 목록·상세·등록·삭제·재고 차감/복구 |
| | `product/service/ProductService.java` · `S3Service.java` | 상품 로직, 이미지 S3 업로드 |
| ordering | `ordering/controller/OrderingController.java` | 주문·내 주문·취소·장바구니·관리자 주문 |
| | `ordering/service/OrderingService.java` · `ProductFeign.java` | 주문 로직, product-service 호출(OpenFeign) |
| | `ordering/domain/Ordering.java` · `CartItem.java` | 주문, 장바구니 엔티티 |
| 공통 | `common/controller/HealthController.java` | `GET /health` |
| | `common/service/CommonExceptionHandler.java` | 예외 → HTTP 상태코드 변환 |

## 3. 프론트엔드 (`msa/frontend/`)

| 경로 | 내용 |
|---|---|
| `src/index.html` | 상품 목록 (대표 페이지) |
| `src/product-detail.html` · `cart.html` · `orders.html` | 상세 · 장바구니 · 주문내역 |
| `src/login.html` · `signup.html` · `mypage.html` · `withdraw.html` | 로그인 · 가입 · 내 정보 · 탈퇴 |
| `src/product-create.html` | 상품 등록(관리자) |
| `src/admin.html` | 관리자 콘솔(탭 7개) |
| `src/assets/app.js` | 공통 스크립트 (헤더/푸터, 인증, 장바구니, 목록/상세, 주문) |
| `src/assets/style.css` | 공통 스타일 (색/여백 변수는 `:root` 한 곳) |
| `nginx/default.conf` · `Dockerfile` · `k8s/depl_svc.yml` | 서빙 설정, 이미지, 배포 |

## 4. 쿠버네티스 공용 매니페스트 (`msa/k8s/`)

| 폴더 | 내용 |
|---|---|
| `k8s-services/` | 서비스 ingress(`server.<도메인>`), HTTPS 인증서·발급자(Let's Encrypt) |
| `k8s-argocd/` | ArgoCD ingress(`argo.<도메인>`) |
| `k8s-hpa/` | 서비스별 HPA(CPU 기준 파드 자동 증감), 부하 테스트용 `stress.yaml` |
| `k8s-monitoring/` | Prometheus(설정·RBAC·배포), Grafana(배포·자동 설정·대시보드), node-exporter, Adminer, 모니터링 ingress |

## 5. 테라폼 (`terraform/`)

| 파일 | 내용 |
|---|---|
| `backend.tf` | state 를 S3 에 저장 (버킷은 `bootstrap/` 이 만듦) |
| `providers.tf` · `variables.tf` · `outputs.tf` | 프로바이더, 변수, 출력 |
| `network.tf` | VPC, 서브넷, NAT |
| `eks.tf` | EKS, 노드 그룹, CI 사용자 접근 권한, 오토스케일러/Grafana 용 IAM 역할(IRSA) |
| `data.tf` | ECR, S3(+공개 읽기), RDS, 쿠버네티스 시크릿, 랜덤 비밀번호 |
| `addons.tf` | helm: ingress-nginx, cert-manager, ArgoCD, 오토스케일러, metrics-server / ArgoCD root app / Grafana 서비스어카운트 |
| `dns.tf` | Route53 서브도메인 CNAME |
| `monitoring.tf` | CloudWatch 알람, 대시보드 |
| `certs.tf` · `cleanup.tf` | 인증서 백업·복원, destroy 정리 |
| `ci.tf` · `credentials.tf` | apply 후 GitHub Actions 실행, 비밀번호 `password.txt` 저장 |
| `scripts/show-credentials.ps1` · `scripts/verify-destroy.ps1` · `scripts/sync-backend.ps1` | 운영 스크립트 |
| `bootstrap/main.tf` | state 버킷 (versioning, 암호화, 공개 차단) |
| `notify/main.tf` | EventBridge → SNS 이메일 알림 |
| `cert-backup/` (git 제외) | HTTPS 인증서 백업 (개인키 포함) |

## 6. 도메인(주소) 구성

| 주소 | 대상 |
|---|---|
| `server.<도메인>` | 쇼핑몰 (`/`=프론트, `/member-service` · `/product-service` · `/ordering-service` = API) |
| `argo.<도메인>` | ArgoCD |
| `grafana.<도메인>` | Grafana |
| `prometheus.<도메인>` | Prometheus |
| `db.<도메인>` | Adminer (Basic 인증 필요) |

## 7. git 에 올라가지 않는 것 (로컬 전용)

`password.txt`, `terraform/cert-backup/`, `terraform.tfstate*`, `.terraform/`, `*.tfvars` — 모두 `.gitignore` 로 제외됩니다.
