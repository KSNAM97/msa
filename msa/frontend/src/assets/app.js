/* ==========================================================================
   NAM97 MALL 공통 스크립트 (프레임워크 없이 순수 JS)
   구성: 1) 유틸  2) 인증  3) 공통 레이아웃(헤더/푸터/토스트)  4) 장바구니  5) 상품 목록/상세  6) 주문내역
   백엔드 호출은 모두 같은 도메인의 /<서비스명>/... 경로 (ingress-nginx -> apigateway 가 라우팅)
   ========================================================================== */
const API_BASE = '';
// 이미지가 없을 때 쓰는 자리표시 (외부 이미지 의존 없이 인라인 SVG)
const PLACEHOLDER_IMAGE = 'data:image/svg+xml;utf8,' + encodeURIComponent(
  '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600"><rect width="100%" height="100%" fill="#f4f4f4"/>' +
  '<text x="50%" y="50%" fill="#b5b5b5" font-size="34" font-family="Arial" text-anchor="middle">NAM97 MALL</text></svg>');

/* ---------- 1) 유틸 ---------- */

// XSS 방지: 서버/사용자 입력값을 innerHTML 에 넣기 전에 반드시 통과시킨다
function esc(value) {
  return String(value == null ? '' : value).replace(/[&<>"']/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
  });
}
function formatPrice(value) { return Number(value || 0).toLocaleString() + '원'; }
function getImageUrl(url) { return url || PLACEHOLDER_IMAGE; }
function getQueryParam(name) { return new URLSearchParams(window.location.search).get(name); }

function showMessage(targetId, message, type) {
  const el = document.getElementById(targetId);
  if (!el) return;
  el.className = 'message ' + type;
  el.textContent = message;          // textContent: 메시지는 HTML 로 해석하지 않음
  el.style.display = 'block';
}

// 화면 우하단 알림. alert() 처럼 흐름을 막지 않고 3.5초 뒤 사라진다. href 를 주면 바로가기 링크가 붙는다
function toast(message, href, linkText) {
  let wrap = document.getElementById('toastWrap');
  if (!wrap) { wrap = document.createElement('div'); wrap.id = 'toastWrap'; wrap.className = 'toast-wrap'; document.body.appendChild(wrap); }
  const t = document.createElement('div');
  t.className = 'toast';
  t.innerHTML = '<span>' + esc(message) + '</span>' + (href ? '<a href="' + esc(href) + '">' + esc(linkText || '보기') + '</a>' : '');
  wrap.appendChild(t);
  setTimeout(function () { t.remove(); }, 3500);
}

// fetch 래퍼: JWT 자동 첨부, 401 이면 로그인 화면으로 보낸다
async function apiRequest(url, options) {
  options = options || {};
  const headers = options.headers || {};
  const token = getToken();
  if (token) headers.Authorization = 'Bearer ' + token;
  // FormData(이미지 업로드)는 브라우저가 boundary 를 포함해 Content-Type 을 직접 설정해야 하므로 건드리지 않는다
  if (!headers['Content-Type'] && !(options.body instanceof FormData)) headers['Content-Type'] = 'application/json';

  const response = await fetch(API_BASE + url, Object.assign({}, options, { headers: headers }));

  if (response.status === 401 && token) {   // 토큰 만료/위조: 저장된 로그인 정보를 지우고 재로그인
    clearAuth();
    window.location.href = '/login.html';
    throw new Error('로그인이 필요합니다.');
  }
  if (!response.ok) {
    throw new Error((await response.text()) || '요청 처리 중 오류가 발생했습니다.');
  }
  const type = response.headers.get('content-type') || '';
  return type.includes('application/json') ? response.json() : response.text();
}

// 상품 목록은 헤더 메뉴/목록/타일이 함께 쓰므로 한 번만 요청해 재사용한다 (실패하면 다음에 다시 시도)
let _productsPromise = null;
function getProducts() {
  if (!_productsPromise) {
    _productsPromise = apiRequest('/product-service/product/list', { method: 'GET', headers: {} })
      .catch(function (e) { _productsPromise = null; throw e; });
  }
  return _productsPromise;
}

/* ---------- 2) 인증 (JWT 는 localStorage 에 보관) ---------- */
function saveAuth(data) { localStorage.setItem('auth', JSON.stringify(data)); }
function getAuth() { try { return JSON.parse(localStorage.getItem('auth')); } catch (e) { return null; } }
function clearAuth() { localStorage.removeItem('auth'); }
function getToken() { const a = getAuth(); return a ? a.token : null; }
function isAdmin() { const a = getAuth(); return !!a && a.role === 'ADMIN'; }

// 로그인이 필요한 페이지/동작에서 호출. 미로그인이면 로그인 화면으로 이동
function guardLogin() {
  if (!getToken()) {
    alert('로그인 후 이용해주세요.');
    window.location.href = '/login.html';
    return false;
  }
  return true;
}

/* ---------- 3) 공통 레이아웃: 모든 페이지의 헤더/푸터를 한 곳에서 생성 ---------- */

// 헤더 아이콘 (외부 아이콘 라이브러리 없이 인라인 SVG)
const ICON = {
  search: '<svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><line x1="16.5" y1="16.5" x2="21" y2="21"/></svg>',
  bag: '<svg viewBox="0 0 24 24"><path d="M5 8h14l-1 12H6L5 8z"/><path d="M9 8V6a3 3 0 0 1 6 0v2"/></svg>',
  user: '<svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="4"/><path d="M4 21c0-4.4 3.6-7 8-7s8 2.6 8 7"/></svg>',
  menu: '<svg viewBox="0 0 24 24"><line x1="4" y1="7" x2="20" y2="7"/><line x1="4" y1="12" x2="20" y2="12"/><line x1="4" y1="17" x2="20" y2="17"/></svg>'
};

// 각 HTML 의 <div id="siteHeader"> / <div id="siteFooter"> 안을 채운다
function renderLayout() {
  const auth = getAuth();
  // 계정 드롭다운: 로그인 여부/권한에 따라 항목이 달라진다. 상품등록은 ADMIN 에게만 노출(서버 권한 검사는 별도 과제)
  const acct = auth
    ? '<div class="who">' + esc(auth.nickname || auth.name || auth.loginId) + '님</div>' +
      '<a href="/orders.html">주문내역</a>' + (isAdmin() ? '<a href="/product-create.html">상품등록</a>' : '') +
      '<button type="button" id="logoutBtn">로그아웃</button>'
    : '<a href="/login.html">로그인</a><a href="/signup.html">회원가입</a>';

  const header = document.getElementById('siteHeader');
  if (header) {
    header.innerHTML =
      '<div class="announce">회원가입 5% 쿠폰 · 3만원 이상 무료배송</div>' +
      '<header class="header"><div class="hwrap">' +
        '<a class="logo" href="/">NAM97</a>' +
        '<nav class="mainnav" id="catNav"><a href="/">ALL</a></nav>' +   // 카테고리는 상품 조회 후 채워진다
        '<div class="icons">' +
          '<button type="button" id="searchToggle" aria-label="검색">' + ICON.search + '</button>' +
          '<a href="/cart.html" aria-label="장바구니">' + ICON.bag + '<span class="count" id="cartCount">' + cartTotalQty() + '</span></a>' +
          '<button type="button" id="acctToggle" aria-label="계정">' + ICON.user + '</button>' +
          '<button type="button" class="menu-btn" id="menuToggle" aria-label="메뉴">' + ICON.menu + '</button>' +
          '<div class="acct-menu" id="acctMenu">' + acct + '</div>' +
        '</div></div>' +
        '<div class="searchbar" id="searchBar"><form action="/" method="get"><input name="q" placeholder="상품명, 카테고리 검색" value="' + esc(getQueryParam('q') || '') + '"><button class="btn" type="submit">SEARCH</button></form></div>' +
      '</header>';

    // 토글 동작: 검색창 / 계정 메뉴 / 모바일 메뉴. 바깥을 클릭하면 계정 메뉴를 닫는다
    const $ = function (id) { return document.getElementById(id); };
    $('searchToggle').onclick = function () { $('searchBar').classList.toggle('open'); if ($('searchBar').classList.contains('open')) $('searchBar').querySelector('input').focus(); };
    $('acctToggle').onclick = function (e) { e.stopPropagation(); $('acctMenu').classList.toggle('open'); };
    $('menuToggle').onclick = function () { $('catNav').classList.toggle('open'); };
    document.addEventListener('click', function () { $('acctMenu').classList.remove('open'); });
    const logout = $('logoutBtn');
    if (logout) logout.onclick = function () { clearAuth(); window.location.href = '/'; };

    // 카테고리 메뉴: 상품의 category 값으로 자동 생성 (별도 카테고리 API 없이 동작). 실패해도 ALL 만 보이고 화면은 정상
    getProducts().then(function (products) {
      const active = getQueryParam('cat') || '';
      const cats = Array.from(new Set(products.map(function (p) { return p.category; }).filter(Boolean)));
      $('catNav').innerHTML = '<a href="/"' + (!active ? ' class="active"' : '') + '>ALL</a>' + cats.map(function (c) {
        return '<a href="/?cat=' + encodeURIComponent(c) + '"' + (c === active ? ' class="active"' : '') + '>' + esc(c) + '</a>';
      }).join('');
    }).catch(function () {});
  }

  const footer = document.getElementById('siteFooter');
  if (footer) {
    footer.innerHTML =
      '<footer class="footer"><div class="container"><div class="cols">' +
        '<div><h4>NAM97 MALL</h4>엄선한 상품을 합리적인 가격에.<br>Kubernetes(MSA) 위에서 운영되는 쇼핑몰입니다.</div>' +
        '<div><h4>Shop</h4><a href="/">전체 상품</a><a href="/cart.html">장바구니</a><a href="/orders.html">주문내역</a></div>' +
        '<div><h4>Member</h4><a href="/login.html">로그인</a><a href="/signup.html">회원가입</a></div>' +
        '<div><h4>Contact</h4>평일 10:00 - 18:00<br>nks026400@gmail.com</div>' +
      '</div>© NAM97 MALL. All rights reserved.</div></footer>';
  }
  initToTop();
}

// 스크롤을 내리면 나타나는 "맨위로" 버튼
function initToTop() {
  const b = document.createElement('button');
  b.className = 'to-top'; b.type = 'button'; b.setAttribute('aria-label', '맨 위로'); b.textContent = '↑';
  b.onclick = function () { window.scrollTo({ top: 0, behavior: 'smooth' }); };
  document.body.appendChild(b);
  window.addEventListener('scroll', function () { b.classList.toggle('show', window.scrollY > 400); });
}

/* ---------- 4) 장바구니 (서버 API 가 없으므로 브라우저 localStorage 에 보관) ---------- */
// ponytail: 기기/브라우저 단위 장바구니. 로그인 계정과 동기화하려면 cart 서비스 추가 필요
function getCart() { try { return JSON.parse(localStorage.getItem('cart')) || []; } catch (e) { return []; } }
function saveCart(cart) { localStorage.setItem('cart', JSON.stringify(cart)); updateCartBadge(); }
function cartTotalQty() { return getCart().reduce(function (s, i) { return s + i.qty; }, 0); }
function updateCartBadge() { const el = document.getElementById('cartCount'); if (el) el.textContent = cartTotalQty(); }

// 같은 상품이 이미 있으면 수량만 더한다. 재고(stock)를 넘지 않게 제한
function addToCart(product, qty) {
  const cart = getCart();
  const item = cart.find(function (i) { return i.id === product.id; });
  const next = Math.min((item ? item.qty : 0) + qty, product.stockQuantity);
  if (item) item.qty = next;
  else cart.push({ id: product.id, name: product.name, price: product.price, imageUrl: product.imageUrl, stock: product.stockQuantity, qty: next });
  saveCart(cart);
}

// 장바구니 화면 렌더링 + 수량변경/삭제/주문하기 이벤트 연결
function renderCartPage() {
  const box = document.getElementById('cartBox');
  if (!box) return;
  const cart = getCart();
  if (!cart.length) {
    box.innerHTML = '<div class="empty">장바구니가 비어 있습니다.<br><br><a class="btn" href="/">쇼핑 계속하기</a></div>';
    return;
  }
  const total = cart.reduce(function (s, i) { return s + i.price * i.qty; }, 0);
  box.innerHTML =
    '<table><thead><tr><th></th><th>상품</th><th>가격</th><th>수량</th><th>합계</th><th></th></tr></thead><tbody>' +
    cart.map(function (i) {
      return '<tr><td><img src="' + esc(getImageUrl(i.imageUrl)) + '" alt=""></td>' +
        '<td><a href="/product-detail.html?id=' + i.id + '">' + esc(i.name) + '</a></td>' +
        '<td>' + formatPrice(i.price) + '</td>' +
        '<td><div class="qty"><button type="button" data-act="dec" data-id="' + i.id + '">-</button>' +
        '<input value="' + i.qty + '" readonly><button type="button" data-act="inc" data-id="' + i.id + '">+</button></div></td>' +
        '<td>' + formatPrice(i.price * i.qty) + '</td>' +
        '<td><button class="btn btn-light" type="button" data-act="del" data-id="' + i.id + '">삭제</button></td></tr>';
    }).join('') +
    '</tbody></table><div class="summary"><span>총 결제금액 <b>' + formatPrice(total) + '</b></span>' +
    '<button class="btn btn-primary btn-lg" id="checkoutBtn" type="button">주문하기</button></div><div id="cartMessage" class="message"></div>';

  // 이벤트 위임: 표 안의 버튼 클릭을 한 곳에서 처리
  box.querySelector('tbody').addEventListener('click', function (e) {
    const btn = e.target.closest('button[data-act]');
    if (!btn) return;
    const id = Number(btn.dataset.id);
    let next = getCart();
    const item = next.find(function (i) { return i.id === id; });
    if (btn.dataset.act === 'inc' && item.qty < item.stock) item.qty++;
    if (btn.dataset.act === 'dec' && item.qty > 1) item.qty--;
    if (btn.dataset.act === 'del') next = next.filter(function (i) { return i.id !== id; });
    saveCart(next);
    renderCartPage();
  });
  document.getElementById('checkoutBtn').addEventListener('click', checkout);
}

// 주문하기: 백엔드에 "장바구니 일괄 주문" API 가 없어서 상품별로 /ordering/create 를 순서대로 호출한다.
// 성공한 상품만 장바구니에서 제거하고, 실패한 상품은 남겨서 사용자가 다시 시도할 수 있게 한다.
async function checkout() {
  if (!guardLogin()) return;
  const btn = document.getElementById('checkoutBtn');
  btn.disabled = true;
  const failed = [];
  let remaining = getCart();
  for (const item of getCart()) {
    try {
      await apiRequest('/ordering-service/ordering/create', {
        method: 'POST', body: JSON.stringify({ productId: item.id, productCount: item.qty })
      });
      remaining = remaining.filter(function (i) { return i.id !== item.id; });
    } catch (e) {
      failed.push(item.name);     // 재고 부족 등
    }
  }
  saveCart(remaining);
  if (failed.length) {
    renderCartPage();
    showMessage('cartMessage', '주문하지 못한 상품: ' + failed.join(', ') + ' (재고를 확인해주세요)', 'error');
  } else {
    window.location.href = '/orders.html?done=1';
  }
}

/* ---------- 5) 상품 목록 / 상세 ---------- */

// 메인 목록: 서버에서 전체를 받아 검색(q)/카테고리(cat)/정렬(sort)을 브라우저에서 처리한다
// ponytail: 상품 수가 수천 개로 늘면 서버 페이징/검색 API 로 교체
async function loadProducts() {
  const list = document.getElementById('productList');
  if (!list) return;
  // 로딩 중에는 회색 자리표시(스켈레톤)를 보여 준다
  list.innerHTML = new Array(8).join('<div class="skeleton"></div>') + '<div class="skeleton"></div>';

  let products;
  try {
    products = await getProducts();
  } catch (e) {
    list.innerHTML = '<div class="empty">상품 목록을 불러오지 못했습니다.</div>';
    return;
  }
  const q = (getQueryParam('q') || '').toLowerCase();
  const cat = getQueryParam('cat') || '';
  const sort = getQueryParam('sort') || 'new';

  const shown = products.filter(function (p) {
    return (!cat || p.category === cat) &&
      (!q || (p.name + ' ' + (p.category || '') + ' ' + (p.description || '')).toLowerCase().includes(q));
  });
  const sorters = {
    'new': function (a, b) { return b.id - a.id; },
    'low': function (a, b) { return a.price - b.price; },
    'high': function (a, b) { return b.price - a.price; }
  };
  shown.sort(sorters[sort] || sorters['new']);

  document.getElementById('listTitle').textContent = q ? 'SEARCH: ' + q : (cat ? cat : 'CURATED BY NAM97');
  document.getElementById('productCount').textContent = shown.length + ' items';
  const sel = document.getElementById('sortSelect');
  sel.value = sort;
  sel.onchange = function () {   // 정렬 변경 시 다른 조건(q, cat)은 유지한 채 URL 만 바꿔 다시 로드
    const p = new URLSearchParams(window.location.search); p.set('sort', sel.value);
    window.location.search = p.toString();
  };

  // 카드 구성: 텍스트(카테고리/이름/가격)가 위, 큰 이미지가 아래. 마우스를 올리면 "ADD TO CART" 가 나타난다
  list.innerHTML = shown.length ? shown.map(function (p) {
    const flag = p.stockQuantity < 1 ? '<span class="flag soldout">SOLD OUT</span>' : (p.stockQuantity < 6 ? '<span class="flag">잔여 ' + p.stockQuantity + '개</span>' : '');
    return '<article class="card"><div class="meta"><div class="brand">' + esc(p.category || 'NAM97') + '</div>' +
      '<a class="name" href="/product-detail.html?id=' + p.id + '">' + esc(p.name) + '</a><div class="price">' + formatPrice(p.price) + '</div>' +
      (isAdmin() ? '<button class="admin-del" type="button" data-del="' + p.id + '">삭제</button>' : '') + '</div>' +   // 관리자에게만 보이는 삭제 버튼
      '<a class="thumb" href="/product-detail.html?id=' + p.id + '"><img loading="lazy" src="' + esc(getImageUrl(p.imageUrl)) + '" alt="' + esc(p.name) + '">' + flag +
      '<button class="quick" type="button" data-add="' + p.id + '"' + (p.stockQuantity < 1 ? ' disabled' : '') + '>ADD TO CART</button></a></article>';
  }).join('') : '<div class="empty">조건에 맞는 상품이 없습니다.</div>';

  // 목록에서 바로 담기 (수량 1). 버튼이 링크(a) 안에 있으므로 기본 이동을 막는다
  list.onclick = function (e) {
    const d = e.target.closest('button[data-del]');
    if (d) {   // 관리자 삭제: 확인 후 DELETE 호출, 성공하면 카드를 화면에서 제거
      const id = Number(d.dataset.del), p = products.find(function (x) { return x.id === id; });
      deleteProduct(id, p ? p.name : '', function () { d.closest('.card').remove(); });
      return;
    }
    const b = e.target.closest('button[data-add]');
    if (!b) return;
    e.preventDefault();
    addToCart(products.find(function (p) { return p.id === Number(b.dataset.add); }), 1);
    toast('장바구니에 담았습니다.', '/cart.html', '장바구니 보기');
  };
}

// 상품 삭제 (관리자). 서버도 ADMIN 이 아니면 403 으로 거절한다. 성공하면 onDone 콜백 실행
async function deleteProduct(id, name, onDone) {
  if (!confirm('"' + name + '" 상품을 삭제할까요? 되돌릴 수 없습니다.')) return;
  try {
    await apiRequest('/product-service/product/' + id, { method: 'DELETE' });
    _productsPromise = null;   // 상품 목록 캐시 무효화 (헤더 카테고리 메뉴 등이 다시 조회하도록)
    toast('삭제했습니다.');
    if (onDone) onDone();
  } catch (e) {
    toast('삭제하지 못했습니다. 관리자 로그인 상태를 확인해주세요.');
  }
}

// 상세: 수량 선택 + 장바구니 담기 + 바로 구매
async function loadProductDetail() {
  const target = document.getElementById('productDetail');
  if (!target) return;
  const id = getQueryParam('id');
  if (!id) { target.innerHTML = '<div class="empty">상품 정보가 없습니다.</div>'; return; }

  let p;
  try {
    p = await apiRequest('/product-service/product/' + encodeURIComponent(id), { method: 'GET', headers: {} });
  } catch (e) {
    target.innerHTML = '<div class="empty">상품 정보를 불러오지 못했습니다.</div>';
    return;
  }
  document.title = p.name + ' - NAM97 MALL';
  const soldOut = p.stockQuantity < 1;
  target.innerHTML =
    '<div class="crumb"><a href="/">HOME</a> / ' + (p.category ? '<a href="/?cat=' + encodeURIComponent(p.category) + '">' + esc(p.category) + '</a> / ' : '') + esc(p.name) + '</div>' +
    '<section class="detail"><div class="detail-img"><img src="' + esc(getImageUrl(p.imageUrl)) + '" alt="' + esc(p.name) + '"></div><div>' +
    '<div class="brand">' + esc(p.category || 'NAM97') + '</div><h1>' + esc(p.name) + '</h1>' +
    '<div class="price">' + formatPrice(p.price) + '</div>' +
    '<p>' + esc(p.description || '상품 설명이 없습니다.') + '</p>' +
    '<p>재고: ' + (soldOut ? '<b>품절</b>' : p.stockQuantity + '개') + '</p>' +
    '<div class="qty"><button type="button" id="qMinus">-</button><input id="qty" value="1" readonly><button type="button" id="qPlus">+</button></div>' +
    '<div class="actions"><button class="btn btn-lg" id="addBtn" type="button"' + (soldOut ? ' disabled' : '') + '>ADD TO CART</button>' +
    '<button class="btn btn-primary btn-lg" id="buyBtn" type="button"' + (soldOut ? ' disabled' : '') + '>BUY NOW</button></div>' +
    '<div id="detailMessage" class="message"></div>' +
    '<div class="info-box">배송: 3만원 이상 무료배송, 오늘 주문 내일 도착<br>반품: 수령 후 7일 이내 가능</div>' +
    (isAdmin() ? '<button class="btn btn-light" id="delBtn" type="button" style="margin-top:18px">이 상품 삭제 (관리자)</button>' : '') +
    '</div></section>';
  const delBtn = document.getElementById('delBtn');   // 관리자에게만 존재. 삭제 성공 시 메인으로 이동
  if (delBtn) delBtn.onclick = function () { deleteProduct(p.id, p.name, function () { setTimeout(function () { window.location.href = '/'; }, 600); }); };

  const qtyEl = document.getElementById('qty');
  document.getElementById('qMinus').onclick = function () { if (+qtyEl.value > 1) qtyEl.value = +qtyEl.value - 1; };
  document.getElementById('qPlus').onclick = function () { if (+qtyEl.value < p.stockQuantity) qtyEl.value = +qtyEl.value + 1; };
  document.getElementById('addBtn').onclick = function () {
    addToCart(p, +qtyEl.value);
    toast('장바구니에 담았습니다.', '/cart.html', '장바구니 보기');
  };
  document.getElementById('buyBtn').onclick = async function () {
    if (!guardLogin()) return;
    this.disabled = true;
    try {
      await apiRequest('/ordering-service/ordering/create', { method: 'POST', body: JSON.stringify({ productId: p.id, productCount: +qtyEl.value }) });
      window.location.href = '/orders.html?done=1';
    } catch (e) {
      this.disabled = false;
      showMessage('detailMessage', '구매에 실패했습니다. 재고를 확인해주세요.', 'error');
    }
  };
}

/* ---------- 6) 주문내역 (백엔드 GET /ordering/my) ---------- */
async function loadOrders() {
  const box = document.getElementById('orderBox');
  if (!box || !guardLogin()) return;
  if (getQueryParam('done')) showMessage('orderMessage', '주문이 완료되었습니다. 감사합니다!', 'success');
  try {
    const orders = await apiRequest('/ordering-service/ordering/my', { method: 'GET', headers: {} });
    if (!orders.length) { box.innerHTML = '<div class="empty">주문 내역이 없습니다.</div>'; return; }
    box.innerHTML = '<table><thead><tr><th></th><th>상품</th><th>수량</th><th>금액</th><th>상태</th><th>주문일</th></tr></thead><tbody>' +
      orders.map(function (o) {
        return '<tr><td><img src="' + esc(getImageUrl(o.imageUrl)) + '" alt=""></td><td>' + esc(o.productName) + '</td><td>' + o.quantity + '</td>' +
          '<td>' + formatPrice(o.price * o.quantity) + '</td><td><span class="status ' + esc(o.status) + '">' + (o.status === 'ORDERED' ? '주문완료' : '취소') + '</span></td>' +
          '<td>' + esc((o.orderedAt || '').replace('T', ' ').slice(0, 16)) + '</td></tr>';
      }).join('') + '</tbody></table>';
  } catch (e) {
    box.innerHTML = '<div class="empty">주문 내역을 불러오지 못했습니다.</div>';
  }
}
