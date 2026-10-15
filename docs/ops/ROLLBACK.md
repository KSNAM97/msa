# 이전 배포로 되돌리기 (롤백)

새 버전에 문제가 생겼을 때 이전 상태로 돌아가는 방법입니다. 이 프로젝트는 **서비스 이미지는 항상 `latest` 태그 하나**로 올리고(`.github/workflows/deploy_ordermsa_with_k8s.yml`), **매니페스트는 ArgoCD 가 Git 을 기준으로 맞춥니다.** 그래서 롤백은 "Git 을 되돌려서 다시 배포" 하는 방식입니다.

## 코드(서비스 이미지)를 되돌릴 때

```powershell
git log --oneline -10                  # 문제를 만든 커밋 확인
git revert <커밋해시>                   # 그 변경을 취소하는 새 커밋 생성
git push origin main                    # CI 가 되돌려진 코드로 이미지를 다시 빌드해 배포
```

- 변경된 서비스 폴더(`msa/member` 등)만 다시 빌드·배포된다(경로 필터).
- 한 서비스만 급히 되돌릴 때: Actions 탭에서 `deploy order order-backend` 를 `workflow_dispatch` 로 수동 실행하면 전체 서비스를 다시 빌드한다.

## 매니페스트(k8s 설정)를 되돌릴 때

`msa/k8s`, `argocd/apps` 의 변경도 같은 방법으로 `git revert` + push 한다. ArgoCD 가 자동 동기화(`prune`, `selfHeal`)로 반영한다.

> `kubectl rollout undo` 만 실행하면 ArgoCD 가 Git 의 새 버전으로 다시 맞춘다. 되돌린 내용은 반드시 Git 에도 남긴다.

## 인프라(테라폼)를 되돌릴 때

```powershell
cd terraform
git revert <커밋해시>
terraform plan     # 무엇이 바뀌는지 먼저 확인 (교체/삭제가 있으면 특히 주의)
terraform apply
```

로드밸런서 종류, RDS 같은 리소스는 되돌릴 때 교체(삭제 후 재생성)될 수 있다. plan 에서 `must be replaced` 를 꼭 확인한다.

## 되돌아갔는지 확인

```powershell
kubectl get applications -n argocd     # Synced / Healthy
kubectl get pods -n ksnam97            # Running, 새로 교체된 파드가 Ready
gh run list --limit 3                  # CI 성공 여부
```

Synced 는 Git 과 클러스터가 같다는 뜻이고, Healthy 는 ArgoCD 가 보기에 정상이라는 뜻이다. 마지막에는 `https://server.ksnam97.com` 에 직접 접속해 확인한다.

## 알아둘 점

- 이미지에 버전 태그가 없어서 ECR 의 이전 이미지로 바로 돌아가는 방식은 쓰지 않는다. 항상 코드를 되돌려 다시 빌드한다.
- DB 구조(JPA `ddl-auto: update`)가 바뀐 변경은 코드를 되돌려도 컬럼이 남는다. 데이터 호환성을 같이 확인한다.
- 이 인프라는 연습용이라 문제가 크면 destroy 후 다시 apply 하는 것이 가장 확실하다(인증서는 백업/복원).

---

[프로젝트 홈](../../README.md) · [실행 방법](../guide/RUNBOOK.md) · [문제 해결](TROUBLESHOOTING.md)
