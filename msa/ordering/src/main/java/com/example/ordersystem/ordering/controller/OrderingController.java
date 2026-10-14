package com.example.ordersystem.ordering.controller;

import com.example.ordersystem.ordering.domain.Ordering;
import com.example.ordersystem.ordering.dto.OrderCreateDto;
import com.example.ordersystem.ordering.service.OrderingService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

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

}
