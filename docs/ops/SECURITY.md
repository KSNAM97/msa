# 보안 점검과 조치

저장소 전체(테라폼, 쿠버네티스 매니페스트, 컨테이너, CI, 앱)를 점검해서 취약점을 고치고, 아직 남은 항목과 이유를 정리했습니다. 기준은 AWS Well-Architected 보안 원칙, CIS 쿠버네티스/AWS 권고, OWASP Top 10 입니다.

## 조치한 항목

| 영역 | 취약점 | 조치 | 파일 |
|---|---|---|---|
| 데이터 암호화 | RDS 디스크가 암호화되지 않음 | `storage_encrypted = true`, 스냅샷에 태그 복사 | `terraform/data.tf` |
| 데이터 암호화 | S3 버킷 암호화가 코드에 없음 | 이미지·CloudTrail 버킷에 SSE-S3 명시 | `terraform/data.tf`, `terraform/cloudtrail.tf` |
| 전송 암호화 | S3 에 HTTP 로 접근 가능 | 두 버킷 정책에 `aws:SecureTransport=false` 거부 추가 | `terraform/data.tf`, `terraform/cloudtrail.tf` |
| 이미지 | 취약한 이미지가 그대로 배포됨 | ECR `scan_on_push`, 저장 암호화 | `terraform/data.tf` |
| 컨테이너 | 서비스가 root 로 실행됨 | 일반 사용자(uid 1000)로 실행 | `msa/{apigateway,member,product,ordering}/Dockerfile` |
| 파드 | 권한 상승·불필요한 capability 허용 | `runAsNonRoot`, `allowPrivilegeEscalation: false`, capability 전부 제거, seccomp `RuntimeDefault` | `msa/*/k8s/depl_svc.yml` (4개 서비스) |
| 모니터링 | Prometheus 가 로그인 없이 공개 | ingress Basic 인증(Adminer 와 같은 계정), Grafana 는 별도 ingress | `msa/k8s/k8s-monitoring/monitoring-Ingress.yml` |
| 모니터링 | 누구나 Prometheus 를 종료·재설정 가능(`--web.enable-lifecycle`) | 옵션 제거 | `msa/k8s/k8s-monitoring/prometheus-depl_svc.yml` |
| 웹 | 서버 버전 노출, 보안 헤더 없음 | `server_tokens off`, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy` | `msa/frontend/nginx/default.conf` |
| CI | 토큰 권한이 기본(넓음) | `permissions: contents: read` | `.github/workflows/deploy_ordermsa_with_k8s.yml` |
| 쿠버네티스 API | 접근 허용 대역을 조절할 수 없음 | `api_allowed_cidrs` 변수 추가(기본 전체, 내 IP 로 줄이는 것이 가능) | `terraform/eks.tf`, `terraform/variables.tf` |

## 원래부터 적용돼 있던 것

- 비밀번호는 BCrypt 로 저장, JWT 서명 키·DB 비밀번호·관리자 비밀번호는 소스가 아니라 쿠버네티스 Secret 으로만 전달(테라폼이 생성).
- 게이트웨이가 `/actuator` 를 차단하고, 서비스 간 내부 호출 엔드포인트는 외부에서 막음. 관리자 기능은 서버에서 권한 확인.
- RDS 는 프라이빗 서브넷, 노드 보안그룹에서 오는 3306 만 허용.
- 상품 이미지 S3 는 `products/*` 읽기만 공개, 업로드·삭제는 전용 IAM 사용자의 최소 권한.
- 입력 검증(이메일, 비밀번호 규칙), 화면 출력 이스케이프(XSS), `password.txt` 와 `cert-backup/` 은 git 제외.
- 모든 도메인 HTTPS(Let's Encrypt), 원격 state 버킷은 버전 관리·암호화·TLS 전용·공개 차단.
- CloudTrail 로 AWS API 작업 이력 기록(로그 변조 검증 켜짐).

## 남은 항목 (연습용 구성의 한계와 이유)

| 항목 | 이유 / 개선 방향 |
|---|---|
| CI 가 장기 IAM 액세스 키 사용 | GitHub OIDC 로 임시 자격 증명으로 바꾸는 것이 표준. 별도 작업이 필요 |
| 쿠버네티스 API 가 인터넷에 열려 있음(인증은 필요) | GitHub 러너 IP 가 고정이 아니라 기본은 전체. 로컬만 쓸 때 `api_allowed_cidrs` 로 제한 |
| RDS 접속이 TLS 강제가 아님 | JDBC URL 과 서버 파라미터(`require_secure_transport`)를 같이 바꿔야 함 |
| 네트워크 정책(NetworkPolicy) 없음 | 파드 간 통신 제한. VPC CNI 의 정책 기능을 켜야 함 |
| 프런트엔드 nginx 는 root 로 실행 | 80 포트 사용 때문. `nginx-unprivileged`(8080)로 바꾸는 작업이 필요 |
| 로그인 시도 횟수 제한(rate limit) 없음 | ingress 의 `limit-req` 또는 게이트웨이 필터로 추가 가능 |
| 탈퇴한 사용자의 JWT 가 만료 전까지 유효 | 토큰 폐기 목록(블랙리스트)이 필요 |
| 단일 NAT · Single-AZ RDS · 백업 0일 | 비용 때문에 의도한 선택 ([RESULTS.md](RESULTS.md)) |

---

[프로젝트 홈](../../README.md) · [문제 해결](TROUBLESHOOTING.md) · [실습 결과와 한계](RESULTS.md)
