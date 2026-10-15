package com.example.ordersystem.ordering.service;

import com.example.ordersystem.ordering.dto.ProductDto;
import com.example.ordersystem.ordering.dto.ProductUpdateStockDto;
import org.springframework.cloud.openfeign.FeignClient;
import org.springframework.web.bind.annotation.*;

// Kubernetes Service DNS(product-service)를 직접 호출
@FeignClient(name = "product-service", url="http://product-service")
public interface ProductFeign {

    @GetMapping("/product/{productId}")
    ProductDto getProductById(@PathVariable("productId") Long productId, @RequestHeader("X-User-Id") String userId);

    @PutMapping("/product/updatestock")
    void updateProductStock(@RequestBody ProductUpdateStockDto productUpdateStockDto);

    // 주문 취소 시 재고 복구 (product-service 의 내부 전용 엔드포인트: 게이트웨이를 거치지 않고 직접 호출)
    @PutMapping("/product/restock")
    void restockProduct(@RequestBody ProductUpdateStockDto productUpdateStockDto);
}
