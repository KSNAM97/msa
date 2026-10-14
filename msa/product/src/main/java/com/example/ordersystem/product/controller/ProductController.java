package com.example.ordersystem.product.controller;

import com.example.ordersystem.product.domain.Product;
import com.example.ordersystem.product.dto.ProductRegisterDto;
import com.example.ordersystem.product.dto.ProductResDto;
import com.example.ordersystem.product.dto.ProductUpdateStockDto;
import com.example.ordersystem.product.service.ProductService;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.util.List;

@RestController
@RequestMapping("/product")
public class ProductController {
    private final ProductService productService;

    public ProductController(ProductService productService) {
        this.productService = productService;
    }

    @PostMapping(value = "/create", consumes = {MediaType.MULTIPART_FORM_DATA_VALUE})
    public ResponseEntity<?> productCreate(@ModelAttribute ProductRegisterDto dto,
                                           @RequestHeader(value = "X-User-Id", required = false) String userId) throws IOException {
        Product product = productService.productCreate(dto, userId);
        return new ResponseEntity<>(product.getId(), HttpStatus.CREATED);
    }

    @GetMapping("/list")
    public ResponseEntity<?> productList(){
        List<ProductResDto> productList = productService.productList();
        return new ResponseEntity<>(productList, HttpStatus.OK);
    }

    @GetMapping("/{id}")
    public ResponseEntity<?> productDetail(@PathVariable Long id){
        ProductResDto productResDto = productService.productDetail(id);
        return new ResponseEntity<>(productResDto, HttpStatus.OK);
    }

    @PutMapping("/updatestock")
    public ResponseEntity<?> updateStock(@RequestBody ProductUpdateStockDto productUpdateStockDto){
        Product product = productService.updateStockQuantity(productUpdateStockDto);
        return new ResponseEntity<>(product.getId(), HttpStatus.OK);
    }

    // 상품 삭제 (관리자 전용). 서버에서 직접 권한을 검사한다: 화면에서 버튼을 숨기는 것만으로는 API 직접 호출을 막을 수 없기 때문.
    // X-User-Role 은 apigateway(JwtAuthFilter)가 JWT 의 role 을 "ROLE_ADMIN" 형태로 넣어 주는 헤더 (클라이언트가 보낸 값은 게이트웨이가 덮어쓴다)
    @DeleteMapping("/{id}")
    public ResponseEntity<?> productDelete(@PathVariable Long id,
                                           @RequestHeader(value = "X-User-Role", required = false) String role){
        if (!"ROLE_ADMIN".equals(role)) {
            return new ResponseEntity<>("관리자만 상품을 삭제할 수 있습니다.", HttpStatus.FORBIDDEN);
        }
        productService.productDelete(id);
        return new ResponseEntity<>(id, HttpStatus.OK);
    }

    @PostMapping("/{id}/purchase")
    public ResponseEntity<?> purchaseProduct(@PathVariable Long id){
        Product product = productService.purchaseProduct(id);
        return new ResponseEntity<>(product.getId(), HttpStatus.OK);
    }
}
