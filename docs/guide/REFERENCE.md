# 함수 / API 참고

> 코드를 읽기 전에 "이 기능이 어느 함수에 있는지" 찾기 위한 색인입니다. 파일 위치는 [STRUCTURE.md](STRUCTURE.md)를 보세요.

## 1. 요청 흐름과 인증 헤더

```
브라우저 → ingress-nginx → apigateway(JwtAuthFilter) → member / product / ordering
```

- 로그인하면 JWT 를 받고, 이후 모든 요청에 `Authorization: Bearer <토큰>` 을 붙입니다.
- 게이트웨이가 토큰을 검증하고 **`X-User-Id`**(회원 번호), **`X-User-Role`**(`ROLE_ADMIN`/`ROLE_USER`) 헤더를 넣어 서비스로 전달합니다. 서비스는 이 두 헤더만 신뢰합니다.
- "내부 전용" API 는 게이트웨이를 거치지 않는 서비스 간 호출만 허용합니다(헤더가 있으면 외부 요청이라 거절).
- 인증 없이 접근 가능한 경로: `POST /member/create`, `/member/doLogin`, `/member/refresh-token`, `GET /product/list`, `GET /product/{id}`.
- 게이트웨이는 `/actuator` 가 들어간 경로를 모두 404 로 막습니다.

## 2. API 목록

권한: **공개** 인증 불필요 · **로그인** 토큰 필요 · **관리자** `ROLE_ADMIN` · **내부** 서비스 간 호출만

주소는 외부 기준 `https://server.<도메인>/<서비스>-service/...` 입니다 (예: `/member-service/member/me`).

### member — `/member`

| 메서드 · 경로 | 권한 | 설명 |
|---|---|---|
| `POST /create` | 공개 | 회원가입 (이메일 형식, 비밀번호 8~64자 영문+숫자 검사) |
| `POST /doLogin` | 공개 | 로그인 → 토큰, 사용자 정보 |
| `POST /refresh-token` | 공개 | 리프레시 토큰으로 새 액세스 토큰 |
| `GET /me` | 로그인 | 내 정보 |
| `PUT /me` | 로그인 | 이름·닉네임·이메일 수정 (이메일 중복/형식 검사) |
| `PUT /password` | 로그인 | 비밀번호 변경 (현재 비밀번호 확인) |
| `POST /withdraw` | 로그인 | 회원탈퇴 (비밀번호 확인, 관리자 계정 불가) |
| `GET /list` | 관리자 | 회원 목록 (비밀번호 제외) |
| `GET /admin/db/tables` | 관리자 | DB 테이블 목록과 행 수 |
| `GET /admin/db/tables/{name}?page=&size=` | 관리자 | 테이블 내용 (읽기 전용, 비밀번호 컬럼 가림) |
| `POST /admin/db/query` | 관리자 | SELECT/SHOW/DESCRIBE 한 문장 실행 (최대 200행, 5초) |
| `GET /admin/metrics/{name}` | 관리자 | Prometheus 지표 (정해진 이름만: `nodes_up`, `node_cpu`, `node_mem`, `pod_cpu`, `pod_mem`, `services_up`, `req_rate`, `err_rate`, `argocd_apps`) |
| `GET /health` | 로그인 | 상태 확인 |

### product — `/product`

| 메서드 · 경로 | 권한 | 설명 |
|---|---|---|
| `GET /list` | 공개 | 상품 목록 (최신순) |
| `GET /{id}` | 공개 | 상품 상세 |
| `POST /create` | 로그인 | 상품 등록 (multipart, 이미지는 S3 `products/`) |
| `DELETE /{id}` | 관리자 | 상품 삭제 |
| `PUT /updatestock` | 내부 | 재고 차감 (주문 시 ordering 이 호출) |
| `PUT /restock` | 내부 | 재고 복구 (주문 취소 시) |
| `GET /health` | 로그인 | 상태 확인 |

### ordering — `/ordering`

| 메서드 · 경로 | 권한 | 설명 |
|---|---|---|
| `POST /create` | 로그인 | 주문 (재고 확인 → product 재고 차감 → 저장) |
| `GET /my` | 로그인 | 내 주문내역 |
| `POST /{id}/cancel` | 로그인/관리자 | 주문 취소 (본인 또는 관리자, 재고 복구) |
| `GET /cart` · `PUT /cart` | 로그인 | 장바구니 조회 / 전체 교체 저장 |
| `GET /admin/all` | 관리자 | 전체 주문 |
| `GET /health` | 로그인 | 상태 확인 |

## 3. 주요 서비스 메서드

| 클래스 | 메서드 | 설명 |
|---|---|---|
| `MemberService` | `save` · `login` · `findMe` · `updateProfile` · `changePassword` · `withdraw` · `findAllMembers` | 회원 로직 |
| `MemberValidator` | `email` · `password` · `text` | 입력 규칙 (화면 안내와 같은 규칙) |
| `JwtTokenProvider` | `createToken` · `createRefreshToken` | JWT 발급 (키는 환경변수 `JWT_SECRET_KEY`, `JWT_SECRET_KEY_RT`) |
| `ProductService` | `productCreate` · `productList` · `productDetail` · `productDelete` · `updateStockQuantity` · `restockQuantity` | 상품 로직 |
| `OrderingService` | `orderFeignCreate` · `myOrders` · `allOrders` · `cancel` · `getCart` · `saveCart` | 주문/장바구니 로직 |
| `Ordering` | `cancel()` | 이미 취소된 주문은 다시 취소 불가 |
| `Product` | `updateStockQuantity` · `restoreStockQuantity` | 재고 차감 / 복구 |

## 4. 프론트엔드 함수 (`assets/app.js`)

### 유틸
| 함수 | 설명 |
|---|---|
| `esc(v)` | HTML 이스케이프 (**화면에 값을 넣을 때 반드시 통과**, XSS 방지) |
| `formatPrice(n)` · `getImageUrl(url)` · `getQueryParam(name)` | 가격 표시, 이미지 없을 때 대체, 주소의 쿼리 값 |
| `showMessage(id, msg, type)` | 폼 아래 성공/오류 메시지 |
| `toast(msg, href, linkText)` | 우하단 알림 |
| `apiRequest(url, options)` | API 호출 래퍼 (토큰 자동 첨부, 401이면 로그인 화면) |
| `getProducts()` | 상품 목록 1회 조회 후 재사용(캐시) |

### 인증
| 함수 | 설명 |
|---|---|
| `saveAuth` · `getAuth` · `clearAuth` · `getToken` | 로그인 정보(localStorage) |
| `isAdmin()` | 관리자 여부 |
| `guardLogin()` | 미로그인이면 로그인 화면으로 |

### 레이아웃
| 함수 | 설명 |
|---|---|
| `renderLayout()` | 모든 페이지의 공지띠·헤더(메뉴/검색/계정)·푸터 생성, 장바구니 동기화 시작 |
| `initToTop()` | 맨위로 버튼 |

### 장바구니
| 함수 | 설명 |
|---|---|
| `getCart` · `saveCart` | 브라우저 저장 + (로그인 시) 서버 저장 |
| `pushCartToServer(cart)` | `PUT /ordering/cart` |
| `syncCartFromServer()` | 로그인 후 서버 장바구니와 병합 (같은 상품은 수량 큰 쪽) |
| `addToCart(product, qty)` | 재고를 넘지 않게 담기 |
| `renderCartPage()` · `checkout()` | 장바구니 화면, 상품별 주문 호출 |
| `cartTotalQty()` · `updateCartBadge()` | 헤더 숫자 |

### 상품 / 주문
| 함수 | 설명 |
|---|---|
| `loadProducts()` | 목록: 검색(`q`) · 카테고리(`cat`) · 정렬(`sort`) |
| `loadProductDetail()` | 상세: 수량, 장바구니, 바로 구매 |
| `deleteProduct(id, name, cb)` | 관리자 삭제 |
| `loadOrders()` · `cancelOrder(id, cb)` | 내 주문내역, 주문 취소 |

### 관리자 콘솔 (`admin.html` 안의 함수)
| 함수 | 설명 |
|---|---|
| `showTab()` · `initTab(id)` | 탭 전환(#해시), 탭을 처음 열 때만 데이터 로드 |
| `metric(name)` | 서버의 지표 조회 API 호출 |
| `check()` · `loadReq()` | 서비스 상태, 요청/에러 |
| `loadArgo()` · `loadCi()` | ArgoCD 앱 상태, GitHub Actions 최근 실행 |
| `loadK8s()` | 노드/파드 사용량 |
| `loadDbTables()` · `showDbTable()` | DB 보기 |
| `loadAdminOrders()` · `loadAdminMembers()` · `renderMembers()` | 주문/회원 관리, 회원 상세 |
| `loadSummary()` · `renderSummary()` | 요약 카드 (데이터가 올 때마다 다시 그림) |

## 5. 테라폼 변수와 출력

| 변수 | 기본값 | 설명 |
|---|---|---|
| `region` | ap-northeast-2 | 리전 |
| `cluster_name` | my-cluster | 워크플로의 클러스터 이름과 같아야 함 |
| `k8s_version` | 1.32 | 오토스케일러 이미지 버전도 맞춰야 함 |
| `node_instance_type` | t3.medium | 노드 크기 |
| `db_instance_class` | db.t4g.micro | RDS 샌드박스 사양 |
| `domain` | ksnam97.com | 기존 Route53 존 이름 |
| `ci_user` | eks-user | GitHub Actions 가 쓰는 IAM 사용자 |
| `github_repo` · `git_repo` | KSNAM97/msa | CI 실행 대상, ArgoCD 가 읽는 저장소 |
| `trigger_ci` | true | apply 후 GitHub Actions 자동 실행 |

| 출력 (`terraform output -raw <이름>`) | 설명 |
|---|---|
| `admin_password` · `grafana_password` · `adminer_password` · `db_password` | 각 비밀번호 (민감 값) |
| `kubeconfig_cmd` · `argocd_admin_pw_cmd` | 접속 설정/ArgoCD 비밀번호 명령 |
| `ecr_urls` · `account_id` · `s3_bucket` · `rds_endpoint` | 리소스 정보 |

## 6. 스크립트 (`terraform/scripts/*.ps1`, PowerShell)

| 스크립트 | 사용 | 설명 |
|---|---|---|
| `show-credentials.ps1` | `.\scripts\show-credentials.ps1 [-Only admin\|grafana\|argocd\|adminer\|db] [-Save]` | 접속 주소와 비밀번호 표시, `-Save` 는 `password.txt` 저장 |
| `verify-destroy.ps1` | `.\scripts\verify-destroy.ps1` | destroy 후 남은 AWS 리소스 점검(읽기 전용) |
| `sync-backend.ps1` | `.\scripts\sync-backend.ps1` | ECR 계정 ID·S3 버킷·CORS 도메인을 소스에 반영 |

## 7. CI 워크플로 단계 (`.github/workflows/deploy_ordermsa_with_k8s.yml`)

1. 체크아웃 → kubectl 설치 → AWS 인증 → EKS 접속 설정 → ECR 로그인
2. `dorny/paths-filter` 로 바뀐 서비스 폴더 감지 (수동 실행(`workflow_dispatch`)이면 전체)
3. 서비스별: 도커 이미지 빌드 → ECR push → `kubectl apply` → `rollout restart`
