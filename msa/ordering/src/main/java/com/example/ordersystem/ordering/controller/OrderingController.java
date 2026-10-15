package com.example.ordersystem.ordering.controller;

import com.example.ordersystem.ordering.domain.Ordering;
import com.example.ordersystem.ordering.dto.CartItemDto;
import com.example.ordersystem.ordering.dto.OrderCreateDto;
import com.example.ordersystem.ordering.service.OrderingService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/ordering")
public class OrderingController {
    private final OrderingService orderingService;

    public OrderingController(OrderingService orderingService) {
        this.orderingService = orderingService;
    }

    @PostMapping("/create")
    public ResponseEntity<?> orderCreate(@RequestBody OrderCreateDto dtos, @RequestHeader("X-User-Id") String userId ){
        Ordering ordering = orderingService.orderFeignCreate(dtos, userId);
        return new ResponseEntity<>(ordering.getId(), HttpStatus.CREATED);
    }

    // 내 주문내역. 사용자 식별은 게이트웨이(JwtAuthFilter)가 토큰에서 꺼내 넣어주는 X-User-Id 헤더를 사용한다
    @GetMapping("/my")
    public ResponseEntity<?> myOrders(@RequestHeader("X-User-Id") String userId) {
        return new ResponseEntity<>(orderingService.myOrders(userId), HttpStatus.OK);
    }

    // 관리자: 전체 주문 조회. X-User-Role 은 게이트웨이가 JWT 의 role 로 넣어 주는 값("ROLE_ADMIN")이라 클라이언트가 위조할 수 없다
    @GetMapping("/admin/all")
    public ResponseEntity<?> allOrders(@RequestHeader("X-User-Id") String userId,
                                       @RequestHeader(value = "X-User-Role", required = false) String role) {
        if (!"ROLE_ADMIN".equals(role)) {
            return new ResponseEntity<>("관리자만 조회할 수 있습니다.", HttpStatus.FORBIDDEN);
        }
        return new ResponseEntity<>(orderingService.allOrders(userId), HttpStatus.OK);
    }

    // 주문 취소: 본인 주문 또는 관리자. 취소하면 재고가 복구된다
    @PostMapping("/{id}/cancel")
    public ResponseEntity<?> cancel(@PathVariable Long id,
                                    @RequestHeader("X-User-Id") String userId,
                                    @RequestHeader(value = "X-User-Role", required = false) String role) {
        orderingService.cancel(id, userId, "ROLE_ADMIN".equals(role));
        return new ResponseEntity<>(id, HttpStatus.OK);
    }

    // 장바구니 조회 / 저장(전체 교체). 로그인한 회원 본인의 장바구니만 다룬다
    @GetMapping("/cart")
    public ResponseEntity<?> getCart(@RequestHeader("X-User-Id") String userId) {
        return new ResponseEntity<>(orderingService.getCart(userId), HttpStatus.OK);
    }

    @PutMapping("/cart")
    public ResponseEntity<?> saveCart(@RequestHeader("X-User-Id") String userId,
                                      @RequestBody List<CartItemDto> items) {
        orderingService.saveCart(userId, items);
        return new ResponseEntity<>(HttpStatus.NO_CONTENT);
    }

}
