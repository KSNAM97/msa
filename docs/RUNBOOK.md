# 실행 방법 (Runbook)

> 인프라를 만들고, 확인하고, 지우는 순서를 정리했습니다. 모든 명령은 **PowerShell** 기준입니다.
> 구조는 [STRUCTURE.md](STRUCTURE.md), 함수/API는 [REFERENCE.md](REFERENCE.md)를 보세요.

## 1. 준비물

| 도구 | 용도 | 확인 |
|---|---|---|
| Terraform ≥ 1.10 | 인프라 | `terraform version` |
| AWS CLI (로그인된 상태) | AWS 접근 | `aws sts get-caller-identity` |
| kubectl | 클러스터 확인 | `kubectl version --client` |
| gh CLI (선택) | `apply` 후 GitHub Actions 자동 실행 | `gh auth status` |
| Git | 소스 관리 | `git --version` |

사전 조건: `ksnam97.com` Route53 호스팅 존이 계정에 있어야 하고(테라폼은 레코드만 추가), GitHub Secrets `AWS_KEY` · `AWS_SECRET` 이 등록돼 있어야 CI가 동작합니다.

## 2. 최초 1회 설정

```powershell
cd terraform\bootstrap
terraform init
terraform apply          # state 저장용 S3 버킷 (이후 계속 유지)
```

(선택) 생성·삭제 알림을 받으려면:

```powershell
cd ..\notify
terraform init
terraform apply -var notify_email=받을@이메일    # 메일의 Confirm subscription 링크를 눌러야 시작
```

## 3. 인프라 만들기 (실습 시작)

```powershell
cd terraform
terraform init           # 처음 또는 모듈/backend 가 바뀌었을 때
terraform plan           # 무엇이 바뀌는지 미리 보기 (선택)
terraform apply          # 약 20~25분
```

`apply` 가 끝나면 **자동으로** 다음이 이어집니다.
1. ArgoCD 가 `argocd/apps` 를 읽어 서비스를 배포
2. GitHub Actions 실행 → 이미지 5개 빌드 후 ECR push (`terraform/ci.tf`)
3. 접속 주소와 비밀번호가 리포 루트의 `password.txt` 에 저장 (`terraform/credentials.tf`)

이미지 빌드가 끝나기 전(약 5분)에는 서비스 파드가 `ImagePullBackOff` 이고 사이트가 503 일 수 있습니다. 정상입니다.

## 4. 확인하기

```powershell
aws eks update-kubeconfig --name my-cluster --region ap-northeast-2   # kubectl 연결
kubectl get nodes
kubectl get pods -A | Select-String -NotMatch 'Running|Completed'    # 비정상 파드만
kubectl -n argocd get applications                                    # 배포 상태
kubectl get certificate -A                                            # HTTPS 인증서 (True 여야 함)
```

접속 주소와 비밀번호:

```powershell
cd terraform
.\show-credentials.ps1           # 전체 표
.\show-credentials.ps1 -Only grafana     # 하나만
```

| 서비스 | 주소 | 로그인 |
|---|---|---|
| 쇼핑몰 | `https://server.ksnam97.com` | 관리자: `admin` / 비밀번호는 위 명령 |
| 관리자 콘솔 | 로그인 후 계정 메뉴 → **관리자** | |
| ArgoCD · Grafana | `https://argo.` · `https://grafana.ksnam97.com` | `admin` |
| DB 관리 | `https://db.ksnam97.com` | Basic 인증 → Adminer 로그인(서버는 자동 입력) |
| Prometheus | `https://prometheus.ksnam97.com` | 로그인 없음 |

## 5. 코드를 고치고 배포하기

| 바꾼 것 | 방법 |
|---|---|
| 서비스/프론트 코드 (`msa/`) | `git add` → `git commit` → `git push` → GitHub Actions 가 **바뀐 서비스만** 빌드·배포 |
| 쿠버네티스 매니페스트 (`msa/k8s`, `argocd`) | push 하면 ArgoCD 가 자동 반영 (최대 3분, 급하면 ArgoCD 에서 Refresh) |
| 테라폼 (`terraform/`) | `terraform plan` 으로 확인 → `terraform apply` |
| 전체 이미지를 다시 빌드 | GitHub → Actions → **Run workflow** (또는 `gh workflow run deploy_ordermsa_with_k8s.yml --ref main`) |

커밋 메시지 끝에 `[skip ci]` 를 붙이면 빌드가 돌지 않습니다(테라폼/문서만 바꿨을 때, 또는 클러스터가 없을 때).

```powershell
git status --short                  # password.txt, cert-backup, tfstate 가 보이면 올리지 말 것
git add .
git commit -m "변경 내용"
git push origin main
```

## 6. 지우기 (실습 종료)

```powershell
cd terraform
terraform destroy        # 약 15~20분. 비용이 드는 리소스를 모두 삭제
.\verify-destroy.ps1     # 남은 리소스 점검 (Route53 존은 기존 존이라 "남음"이 정상)
```

- destroy 때 HTTPS 인증서가 `terraform/cert-backup/` 에 백업되고, 다음 `apply` 에서 복원됩니다(Let's Encrypt 발급 한도 회피).
- state 버킷(`bootstrap`)과 알림(`notify`)은 유지됩니다. 알림 메일로 삭제 여부도 확인할 수 있습니다.

## 7. 문제 해결

| 증상 | 원인 / 해결 |
|---|---|
| 사이트 503, 파드 `ImagePullBackOff` | 이미지 빌드 중. Actions 탭에서 성공할 때까지 대기 |
| 사이트 504 / 일부만 느림 | 노드 보안그룹 규칙 확인 (`eks.tf` 의 `node_security_group_additional_rules`) |
| 인증서 `False` | Let's Encrypt 발급 한도(같은 이름 7일 5회). `kubectl describe certificate -n soldesk server-ksnam97-com-tls` 의 메시지에 재시도 시각 표시. destroy 시 백업/복원으로 예방 |
| `terraform` 이 state 오류 | `terraform init` 다시. 다른 곳에서 apply 중이면 잠금 때문에 대기 |
| 관리자 콘솔 지표가 "가져오지 못했습니다" | Prometheus 파드 상태 확인(`kubectl -n monitoring get pods`) |
| Grafana CloudWatch 대시보드가 비어 있음 | CloudWatch 지표 수집에 몇 분 소요, 그래도 비면 Grafana 파드의 IRSA 확인 |
| CI 가 `No cluster found` | 클러스터가 없을 때 push 됨 → `apply` 후 다시 실행 |
| `password.txt` 가 없음 | `terraform\show-credentials.ps1 -Save` 로 다시 생성 |

## 8. 안전 수칙

- `password.txt`, `terraform/cert-backup/`, `terraform.tfstate*` 는 절대 git 에 올리지 않습니다(이미 제외 설정됨).
- 비밀번호는 `apply` 때마다 바뀝니다. 토큰도 JWT 키가 바뀌어 다시 로그인해야 합니다.
- 쓰지 않을 때는 `terraform destroy` 로 비용을 끊습니다.
