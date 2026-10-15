# 변경 이력

큰 변경만 최신순으로 기록합니다. 자세한 내용은 커밋 메시지(수정한 파일 목록 포함)를 봅니다.

## 2026-10-15

- **알림/모니터링**
  - 주문이 성공하면 SNS 이메일 알림, 남은 재고가 5개 이하이면 `LOW STOCK` 표시 (`OrderNotifier`, IRSA)
  - Grafana 알람 규칙 6개(서비스 중지, 파드 CPU, JVM 힙, 5xx, 응답 지연, 노드 CPU) → SNS 이메일
  - Grafana `Spring Boot JVM` 대시보드 추가 (총 7종), NLB 대시보드(`AWS/NetworkELB`)
  - 관리자 콘솔 15초 자동 갱신(폴링)
- **보안** ([SECURITY.md](docs/SECURITY.md))
  - RDS 디스크 암호화, S3 암호화·HTTP 거부, ECR 이미지 스캔
  - 서비스 non-root 실행, 파드 보안 설정, nginx 보안 헤더
  - Prometheus Basic 인증, CI 토큰 최소 권한
- **인프라**
  - Classic ELB → NLB 전환, S3 Gateway Endpoint, CloudTrail 추가
  - 네임스페이스 `soldesk` → `ksnam97`
  - 원격 state(S3), 인증서 백업/복원, destroy 검증 스크립트
- **CI**: PR 컴파일 검사(`pr-check.yml`)
- **문서**: 문제 해결, 롤백, 실습 결과, 보안, 구성도(SVG) 추가

## 이전

- 마이크로서비스 쇼핑몰(회원·상품·주문·게이트웨이·프런트엔드), Terraform 인프라, GitHub Actions + ArgoCD 배포, Prometheus/Grafana, 관리자 콘솔 구축
