package com.example.ordersystem.ordering.service;

import com.example.ordersystem.ordering.domain.CartItem;
import com.example.ordersystem.ordering.domain.OrderStatus;
import com.example.ordersystem.ordering.domain.Ordering;
import com.example.ordersystem.ordering.dto.CartItemDto;
import com.example.ordersystem.ordering.dto.OrderCreateDto;
import com.example.ordersystem.ordering.dto.OrderResDto;
import com.example.ordersystem.ordering.dto.ProductDto;
import com.example.ordersystem.ordering.dto.ProductUpdateStockDto;
import com.example.ordersystem.ordering.repository.CartItemRepository;
import com.example.ordersystem.ordering.repository.OrderingRepository;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.client.RestTemplate;

import java.util.List;


@Service
@Transactional
public class OrderingService {
    private final OrderingRepository orderingRepository;
    private final CartItemRepository cartItemRepository;
    private final RestTemplate restTemplate;
    private final ProductFeign productFeign;

    public OrderingService(OrderingRepository orderingRepository, CartItemRepository cartItemRepository, RestTemplate restTemplate, ProductFeign productFeign) {
        this.orderingRepository = orderingRepository;
        this.cartItemRepository = cartItemRepository;
        this.restTemplate = restTemplate;
        this.productFeign = productFeign;
    }

    public Ordering orderCreate(OrderCreateDto orderDto, String userId){

//        product get 요청
        String productGetUrl = "http://product-service/product/"+orderDto.getProductId();
        HttpHeaders httpHeaders = new HttpHeaders();
        httpHeaders.set("X-User-Id", userId);
        HttpEntity<String> httpEntity = new HttpEntity<>(httpHeaders);
        ResponseEntity<ProductDto> response =  restTemplate.exchange(productGetUrl, HttpMethod.GET, httpEntity, ProductDto.class);
        ProductDto productDto = response.getBody();
        int quantity = orderDto.getProductCount();
        if(productDto.getStockQuantity() < quantity){
            throw new IllegalArgumentException("재고 부족");
        }else {

//        product put 요청
            String productPutUrl = "http://product-service/product/updatestock";
            httpHeaders.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<ProductUpdateStockDto> updateEntity = new HttpEntity(
                    ProductUpdateStockDto.builder().productId(orderDto.getProductId())
                            .productQuantity(orderDto.getProductCount()).build()
                    , httpHeaders
            );
            restTemplate.exchange(productPutUrl, HttpMethod.PUT, updateEntity, Void.class);
        }
        Ordering ordering = Ordering.builder()
                .memberId(Long.parseLong(userId))
                .productId(orderDto.getProductId())
                .quantity(orderDto.getProductCount())
                .build();
        orderingRepository.save(ordering);
        return  ordering;
    }


    public Ordering orderFeignCreate(OrderCreateDto orderDto, String userId){

        ProductDto productDto = productFeign.getProductById(orderDto.getProductId(), userId);

        int quantity = orderDto.getProductCount();
        if(productDto.getStockQuantity() < quantity){
            throw new IllegalArgumentException("재고 부족");
        }else {
            ProductUpdateStockDto dto = ProductUpdateStockDto.builder().productId(orderDto.getProductId())
                    .productQuantity(orderDto.getProductCount()).build();
            productFeign.updateProductStock(dto);

        }
        Ordering ordering = Ordering.builder()
                .memberId(Long.parseLong(userId))
                .productId(orderDto.getProductId())
                .quantity(orderDto.getProductCount())
                .build();
        orderingRepository.save(ordering);
        return  ordering;
    }

    // 내 주문내역: 주문마다 product-service 를 호출해 상품명/가격/이미지를 채운다.
    // ponytail: 주문 N건 = Feign N회 호출. 주문이 많아지면 주문 시점에 상품명/가격을 주문 테이블에 저장하거나 bulk 조회 API 로 교체
    @Transactional(readOnly = true)
    public List<OrderResDto> myOrders(String userId) {
        return toResDtos(orderingRepository.findByMemberIdOrderByIdDesc(Long.parseLong(userId)), userId);
    }

    // 관리자용 전체 주문. (권한 검사는 컨트롤러에서 X-User-Role 로 수행)
    @Transactional(readOnly = true)
    public List<OrderResDto> allOrders(String adminUserId) {
        return toResDtos(orderingRepository.findAllByOrderByIdDesc(), adminUserId);
    }

    // 주문 목록 -> 응답 DTO 변환 (상품 정보는 product-service 에서 조회)
    private List<OrderResDto> toResDtos(List<Ordering> orders, String requesterId) {
        return orders.stream().map(order -> {
            ProductDto product = null;
            try {
                product = productFeign.getProductById(order.getProductId(), requesterId);
            } catch (Exception e) {
                // 삭제된 상품 등으로 조회 실패해도 주문내역 전체가 실패하지 않게 한다
            }
            return OrderResDto.builder()
                    .id(order.getId())
                    .memberId(order.getMemberId())
                    .productId(order.getProductId())
                    .productName(product != null ? product.getName() : "(삭제된 상품)")
                    .price(product != null ? product.getPrice() : 0)
                    .imageUrl(product != null ? product.getImageUrl() : null)
                    .quantity(order.getQuantity())
                    .status(order.getOrderStatus().name())
                    .orderedAt(order.getCreatedTime())
                    .build();
        }).toList();
    }

    // 주문 취소: 본인 주문이거나 관리자일 때만 가능. 순서: (1) 재고 복구 (2) 상태 변경.
    // 재고 복구가 실패하면 예외로 끝나고 상태는 바뀌지 않는다(트랜잭션 롤백)
    // ponytail: 서비스 간 분산 트랜잭션이 아니라서, 재고 복구 성공 직후 DB 오류가 나면 불일치 가능. 운영에서는 사가/아웃박스 패턴 검토
    public void cancel(Long orderId, String userId, boolean admin) {
        Ordering order = orderingRepository.findById(orderId)
                .orElseThrow(() -> new jakarta.persistence.EntityNotFoundException("없는 주문입니다."));
        if (!admin && !order.getMemberId().equals(Long.parseLong(userId))) {
            throw new SecurityException("본인의 주문만 취소할 수 있습니다.");
        }
        if (order.getOrderStatus() == OrderStatus.CANCELED) {
            throw new IllegalArgumentException("이미 취소된 주문입니다.");
        }
        productFeign.restockProduct(ProductUpdateStockDto.builder()
                .productId(order.getProductId()).productQuantity(order.getQuantity()).build());
        order.cancel();
    }

    // ---------- 장바구니 (서버 저장) ----------

    @Transactional(readOnly = true)
    public List<CartItemDto> getCart(String userId) {
        return cartItemRepository.findByMemberId(Long.parseLong(userId)).stream()
                .map(c -> new CartItemDto(c.getProductId(), c.getQuantity())).toList();
    }

    // 장바구니 전체 교체: 기존 줄을 지우고 받은 목록으로 다시 저장한다(수량 변경/삭제/비우기가 모두 이 한 호출로 처리됨)
    // 같은 상품이 여러 줄이면 수량을 합치고, 수량이 1 미만인 줄은 무시한다
    public void saveCart(String userId, List<CartItemDto> items) {
        Long memberId = Long.parseLong(userId);
        cartItemRepository.deleteByMemberId(memberId);
        cartItemRepository.flush();   // 삭제를 먼저 DB 에 반영해야 (memberId, productId) 유니크 제약과 충돌하지 않는다
        java.util.Map<Long, Integer> merged = new java.util.LinkedHashMap<>();
        for (CartItemDto item : items) {
            if (item.getProductId() == null || item.getQuantity() == null || item.getQuantity() < 1) continue;
            merged.merge(item.getProductId(), item.getQuantity(), Integer::sum);
        }
        merged.forEach((productId, qty) -> cartItemRepository.save(
                CartItem.builder().memberId(memberId).productId(productId).quantity(qty).build()));
    }

}
