# 문제 해결 기록

만들고 지우기를 반복하며 실제로 겪은 문제를 **증상 → 원인 → 해결** 순서로 정리했습니다. 오류 문구만 보지 않고 파드·이벤트·로그·AWS 리소스를 함께 확인한 과정입니다.

## 1. 인증서가 새로 발급되지 않거나 `False` 로 남음

- **증상**: destroy 후 다시 apply 하면 `kubectl get certificate -A` 가 `False`. `kubectl describe certificate` 에 rate limit 메시지.
- **원인**: Let's Encrypt 는 같은 도메인 조합을 7일에 5회까지만 발급한다. 만들고 지우기를 반복하면 한도에 걸린다.
- **해결**: destroy 직전에 TLS 시크릿 4개를 `terraform/cert-backup/` 에 저장하고(`cleanup.tf`), apply 때 ArgoCD 보다 먼저 복원한다(`certs.tf`). cert-manager 는 복원된 유효한 인증서를 그대로 쓴다.
- **주의**: 백업은 destroy 때 갱신된다. 네임스페이스 이름을 바꿨다면 백업 파일 이름과 내부 `namespace` 도 같이 바꿔야 한다. 폴더는 개인키가 들어 있어 git 에 올리지 않는다.

## 2. Grafana 의 CloudWatch 패널이 `No data`

- **증상**: 지표 빌더로 만든 패널이 비어 있다. 같은 지표를 AWS 콘솔에서는 볼 수 있다.
- **원인**: Grafana 13 의 CloudWatch 빌더 쿼리가 이 환경에서 데이터를 돌려주지 않았다. 검색식(SEARCH) 쿼리만 정상 동작했다.
- **해결**: 모든 CloudWatch 패널을 `SORT(SEARCH('{네임스페이스,차원} MetricName="..."', '통계', 주기), MAX, DESC, N)` 형태로 바꿨다. 삭제된 예전 리소스의 기록이 섞여 보이지 않도록 상위 N 개만 보여준다.

## 3. 로드밸런서 대시보드가 비어 있음 (Classic ELB → NLB)

- **증상**: `AWS/NetworkELB` 기준 패널이 비어 있다.
- **원인**: ingress-nginx 서비스에 주석이 없으면 Classic ELB(`AWS/ELB`)가 만들어진다. 지표 네임스페이스가 서로 다르다.
- **해결**: 서비스에 `aws-load-balancer-type: nlb` 주석을 넣어 NLB 로 만들고 대시보드를 `AWS/NetworkELB` 로 맞췄다. 로드밸런서 종류는 만든 뒤 바꿀 수 없어 helm 릴리스를 `-replace` 로 교체했다(DNS 가 새 주소로 바뀌며 몇 분 끊김).
- **주의**: 새 NLB 는 만든 직후 약 10분간 CloudWatch 지표가 없다. 그동안 패널이 비어 보이는 것은 정상이다. destroy 대기(`wait_lb_gone`)는 ALB/NLB 와 클래식 ELB 를 모두 확인한다.

## 4. ArgoCD 앱이 계속 `OutOfSync`

- **증상**: 인증서 관련 앱이 Synced 로 돌아오지 않는다.
- **원인**: Certificate 를 매니페스트와 ingress(cert-manager ingress-shim)가 모두 만들어 spec 을 서로 덮어쓴다.
- **해결**: 앱에 `ignoreDifferences`(Certificate `/spec`) 와 `RespectIgnoreDifferences=true` 를 넣었다. 클러스터에서 덤프한 `stress.yaml` 은 깨끗한 Deployment 매니페스트로 다시 썼다.

## 5. 처음 apply 직후 파드가 `ErrImagePull`

- **증상**: apply 가 끝났는데 서비스 파드가 `ErrImagePull`, 사이트는 503.
- **원인**: 새로 만든 ECR 이 비어 있다. 이미지는 apply 끝의 CI 실행이 빌드해서 올린다.
- **해결**: 기다린다. `gh run list` 가 `success` 가 되면 파드가 Running 이 된다. 인증서 신뢰 오류도 ingress 가 만들어진 직후 잠시 나타난다.

## 6. apply 가 중간에 멈춘 채로 남음

- **증상**: 노드·RDS·NLB 는 있는데 ArgoCD 와 서비스 파드가 없다. terraform 프로세스도 없다.
- **해결**: 같은 폴더에서 `terraform plan` 으로 남은 리소스만 나오는지 보고, `terraform apply` 를 다시 실행하면 이어서 만든다. 출력을 `Select-Object -First` 등으로 자르면 terraform 이 중간에 끝나므로 로그 파일로 보낸다.

## 7. 실행 환경에서 만난 오류

| 문제 | 해결할 때 확인한 내용 |
|---|---|
| `.ps1` 한글이 깨지거나 스크립트 오류 | Windows PowerShell 5.1 은 BOM 없는 UTF-8 을 ANSI 로 읽는다. BOM 을 붙여 UTF-8 로 저장 |
| `-replace=helm_release.x` 가 인식되지 않음 | PowerShell 에서 인자를 따옴표로 감싼다: `"-replace=helm_release.x"` |
| `terraform output` 이 apply 중에는 비어 있음 | 비밀번호를 환경변수로 넘겨 자격 증명 스크립트에서 쓴다 |
| SG 규칙 설명에 `>` 를 쓰면 거부됨 | 특수문자를 빼고 일반 문장으로 쓴다 |
| 이름에 em dash 를 쓰면 AWS 가 거부 | 리소스 이름과 설명에는 하이픈을 쓴다 |
| 커밋을 올린 뒤 push 거부 | GitHub 에서 파일을 추가했을 때는 `git pull --rebase origin main` 후 push |

---

[프로젝트 홈](../../README.md) · [실행 방법](../guide/RUNBOOK.md) · [롤백](ROLLBACK.md) · [실습 결과](RESULTS.md)
