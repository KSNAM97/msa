package com.example.ordersystem.ordering.dto;


import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@AllArgsConstructor
@NoArgsConstructor
@Data
@Builder
public class ProductDto {
    private Long id;
    private String name;
    private int price;
    private int stockQuantity;
    // 주문내역 화면에서 상품 이미지를 보여주기 위해 추가 (product-service 응답에 이미 포함된 필드)
    private String imageUrl;
}
