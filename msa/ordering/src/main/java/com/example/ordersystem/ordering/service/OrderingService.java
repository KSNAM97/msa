package com.example.ordersystem.ordering.service;

import com.example.ordersystem.ordering.domain.Ordering;
import com.example.ordersystem.ordering.dto.OrderCreateDto;
import com.example.ordersystem.ordering.dto.OrderResDto;
import com.example.ordersystem.ordering.dto.ProductDto;
import com.example.ordersystem.ordering.dto.ProductUpdateStockDto;
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
    private final RestTemplate restTemplate;
    private final ProductFeign productFeign;

    public OrderingService(OrderingRepository orderingRepository, RestTemplate restTemplate, ProductFeign productFeign) {
        this.orderingRepository = orderingRepository;
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
        return orderingRepository.findByMemberIdOrderByIdDesc(Long.parseLong(userId)).stream().map(order -> {
            ProductDto product = null;
            try {
                product = productFeign.getProductById(order.getProductId(), userId);
            } catch (Exception e) {
                // 삭제된 상품 등으로 조회 실패해도 주문내역 전체가 실패하지 않게 한다
            }
            return OrderResDto.builder()
                    .id(order.getId())
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

}
