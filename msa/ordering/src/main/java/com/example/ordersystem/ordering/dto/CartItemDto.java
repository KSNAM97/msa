package com.example.ordersystem.ordering.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

// 장바구니 요청/응답 한 줄. 상품명/가격/이미지는 저장하지 않고 화면이 상품 목록에서 채운다(가격 변경이 바로 반영되도록)
@Data
@NoArgsConstructor
@AllArgsConstructor
public class CartItemDto {
    private Long productId;
    private Integer quantity;
}
