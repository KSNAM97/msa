# apply 후 실행: 접속 주소와 관리자 계정(비밀번호)을 출력한다. (읽기 전용: 아무것도 변경하지 않음)
#   .\show-credentials.ps1                  전체를 표로 출력
#   .\show-credentials.ps1 -Only admin      쇼핑몰 관리자 비밀번호만
#   .\show-credentials.ps1 -Only grafana    Grafana 비밀번호만
#   .\show-credentials.ps1 -Only argocd     ArgoCD 비밀번호만
#   .\show-credentials.ps1 -Save            전체 출력 + 저장소 루트의 password.txt 에 저장
#       (password.txt 는 루트 .gitignore 로 git 에서 제외됨. 내 PC 에만 남는다. apply 할 때마다 -Save 로 덮어쓰기)
# 비밀번호는 apply 때마다 랜덤으로 새로 만들어진다.
# - 쇼핑몰 admin / Grafana: terraform output   - ArgoCD: 클러스터 시크릿(argocd-initial-admin-secret)
# 비밀번호가 화면에 그대로 출력되므로 화면 공유/녹화 중에는 실행하지 말 것.
param(
  [ValidateSet('all', 'admin', 'grafana', 'argocd')][string]$Only = 'all',
  [switch]$Save,
  [string]$Domain = 'ksnam97.com', [string]$Cluster = 'my-cluster', [string]$Region = 'ap-northeast-2'
)
$ErrorActionPreference = 'Stop'

# 서비스별 비밀번호를 가져오는 함수 (필요한 것만 호출해서 불필요한 조회를 피한다)
# terraform apply 도중(credentials.tf 가 자동 호출)에는 state 가 잠겨 있어 output 을 읽을 수 없으므로,
# 테라폼이 환경변수(TF_ADMIN_PW / TF_GRAFANA_PW)로 값을 직접 넘겨준다. 평소 수동 실행 때는 terraform output 을 읽는다
function Get-AdminPw   { if ($env:TF_ADMIN_PW)   { return $env:TF_ADMIN_PW };   Push-Location $PSScriptRoot; try { terraform output -raw admin_password } finally { Pop-Location } }
function Get-GrafanaPw { if ($env:TF_GRAFANA_PW) { return $env:TF_GRAFANA_PW }; Push-Location $PSScriptRoot; try { terraform output -raw grafana_password } finally { Pop-Location } }
function Get-ArgoPw {
  # ArgoCD 초기 비밀번호는 base64 로 저장돼 있어 디코딩한다 (kubectl 접속 설정 후 조회)
  aws eks update-kubeconfig --name $Cluster --region $Region | Out-Null
  $b64 = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>$null
  if ($b64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) } else { '(아직 없음 - ArgoCD 가 뜬 뒤 다시 실행)' }
}

# 하나만 요청하면 비밀번호 값만 출력 (복사해서 붙여넣기 쉽게)
switch ($Only) {
  'admin'   { Get-AdminPw;   return }
  'grafana' { Get-GrafanaPw; return }
  'argocd'  { Get-ArgoPw;    return }
}

$rows = @(
  [pscustomobject]@{ 서비스 = '쇼핑몰 관리자'; 주소 = "https://server.$Domain/login.html"; 아이디 = 'admin'; 비밀번호 = (Get-AdminPw) },
  [pscustomobject]@{ 서비스 = 'Grafana';       주소 = "https://grafana.$Domain";           아이디 = 'admin'; 비밀번호 = (Get-GrafanaPw) },
  [pscustomobject]@{ 서비스 = 'ArgoCD';        주소 = "https://argo.$Domain";              아이디 = 'admin'; 비밀번호 = (Get-ArgoPw) },
  [pscustomobject]@{ 서비스 = 'Prometheus';    주소 = "https://prometheus.$Domain";        아이디 = '(로그인 없음)'; 비밀번호 = '-' }
)
$rows | Format-Table -AutoSize

# -Save: 저장소 루트(terraform 폴더의 상위)의 password.txt 에 저장. .gitignore 로 git 제외. 비밀번호는 apply 마다 바뀌므로 매번 덮어쓴다
if ($Save) {
  $file = Join-Path (Split-Path $PSScriptRoot -Parent) 'password.txt'
  $lines = @("저장 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", "※ 이 파일은 git 에 올리지 않습니다 (.gitignore). apply 할 때마다 새 비밀번호로 바뀝니다.", '')
  foreach ($r in $rows) { $lines += "[$($r.서비스)]  $($r.주소)", "  아이디: $($r.아이디)", "  비밀번호: $($r.비밀번호)", '' }
  Set-Content -Path $file -Value $lines -Encoding UTF8
  Write-Host "저장됨: $file  (git 제외)" -ForegroundColor Green
}
