# apply 후 실행: 테라폼 output 값으로 ../aws-msa-backend 의 하드코딩 값을 자동 교체 (여러 번 실행해도 안전)
# 사용: .\sync-backend.ps1            (commit/push는 직접)
param([string]$Backend = (Join-Path $PSScriptRoot '..'), [string]$Domain = 'ksnam97.com')
$ErrorActionPreference = 'Stop'

Push-Location $PSScriptRoot
try {
  $acct   = terraform output -raw account_id
  $bucket = terraform output -raw s3_bucket
} finally { Pop-Location }
if ($acct -notmatch '^\d{12}$' -or -not $bucket) { throw 'terraform output을 읽지 못했습니다. apply 완료 후 실행하세요.' }

# 파일, 정규식, 치환값
$rules = @(
  @{ Glob = '*.yml';  Re = '\d{12}(\.dkr\.ecr\.)';                        To = "$acct`$1" },           # ECR 계정 ID (워크플로 + depl_svc.yml)
  @{ Glob = 'application-prod.yml'; Re = '(bucket:\s*)\S+';               To = "`${1}$bucket" },       # S3 버킷
  @{ Glob = 'application-prod.yml'; Re = "'https://server\.aws-esk\.com'"; To = "'https://server.$Domain'" } # CORS
)

$utf8 = New-Object System.Text.UTF8Encoding($false)
$changed = @()
foreach ($r in $rules) {
  Get-ChildItem $Backend -Recurse -File -Filter $r.Glob |
    Where-Object { $_.FullName -notmatch '\\(\.git|build|node_modules)\\' } | ForEach-Object {
      $old = [IO.File]::ReadAllText($_.FullName)
      $new = [regex]::Replace($old, $r.Re, $r.To)
      if ($new -ne $old) {
        [IO.File]::WriteAllText($_.FullName, $new, $utf8)
        $changed += $_.FullName.Substring((Resolve-Path $Backend).Path.Length + 1)
      }
    }
}

if ($changed) { "수정됨:"; $changed | Sort-Object -Unique | ForEach-Object { "  $_" } } else { '변경 없음 (이미 일치)' }
"`n다음: aws-msa-backend 에서 git commit/push -> GitHub Actions가 ECR로 이미지 push, ArgoCD 배포"
"GitHub Secrets(AWS_KEY, AWS_SECRET)는 직접 등록 필요"
