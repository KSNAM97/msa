# 실습 결과와 한계

직접 만들고 지우기를 반복하며 확인한 내용과, 이 구성이 보장하지 않는 것을 정리했습니다.

## 확인한 결과

| 실습 | 확인한 결과 |
|---|---|
| 인프라 생성 | `terraform apply` 한 번으로 VPC, EKS, RDS, S3, ECR, ingress-nginx(NLB), cert-manager, ArgoCD, DNS, 모니터링 생성 |
| 배포 흐름 | GitHub push → Actions 이미지 빌드 → ECR → ArgoCD/kubectl 반영 → 사이트 변경 확인 |
| HTTPS | 도메인 5개(server, argo, grafana, prometheus, db) 인증서 발급·복원 후 접속 |
| 로드밸런서 교체 | Classic ELB → NLB 교체, 타깃 정상, DNS 전환, 예전 ELB·보안그룹 삭제 |
| 인증서 백업 | destroy 때 저장, apply 때 복원해서 Let's Encrypt 발급 한도 회피 |
| 모니터링 | Prometheus 수집, Grafana 대시보드 6종(개요, 쿠버네티스, RDS, EC2, NLB, 로그) |
| 알림 | 리소스 생성·삭제 이메일(SNS + EventBridge), CloudWatch 경보 |
| 앱 기능 | 가입·로그인, 상품 등록·삭제, 장바구니 주문, 주문 취소, 관리자 콘솔 |
| 원격 state | S3 백엔드 + 잠금 파일, 이전 후 plan 에서 No changes |
| destroy 점검 | `verify-destroy.ps1` 결과 기존 Route53 존 1개만 남음, 나머지 전부 삭제 |
| 이름 변경 | 네임스페이스 `soldesk` → `ksnam97` 반영 후 재생성, 서비스 파드 5개 Running |

## 실습 비용을 고려한 구성 (한계)

- NAT 게이트웨이는 1개(단일 AZ 장애 시 외부 통신 불가).
- RDS 는 Single-AZ, 백업 보존 0일, 퍼블릭 접근 없음(샌드박스용).
- 서비스는 파드 1개씩이고 HPA 가 부하 때 늘린다.
- Prometheus 에는 로그인이 없다(도메인만 알면 조회 가능).
- 탈퇴한 사용자의 JWT 는 만료 전까지 유효하다.
- 주문 취소는 분산 트랜잭션이 아니다(서비스 호출 실패 시 수동 정리가 필요할 수 있음).

모든 장애에서 무중단을 보장하는 운영 구성이 아니라, **배포 자동화, 복구, 모니터링을 직접 확인하는 연습 환경**입니다.

---

[프로젝트 홈](../README.md) · [문제 해결](TROUBLESHOOTING.md) · [롤백](ROLLBACK.md)
