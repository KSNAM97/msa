package com.example.ordersystem.ordering.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

// 주문내역 응답: 주문 정보 + product-service 에서 가져온 상품 정보(이름/가격/이미지)
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class OrderResDto {
    private Long id;
    private Long productId;
    private String productName;
    private Integer price;
    private String imageUrl;
    private Integer quantity;
    private String status;
    private LocalDateTime orderedAt;
}
