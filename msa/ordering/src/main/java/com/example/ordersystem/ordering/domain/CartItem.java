package com.example.ordersystem.ordering.domain;

import com.example.ordersystem.common.domain.BaseTimeEntity;
import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

// 서버에 저장되는 장바구니 한 줄. 로그인한 회원의 장바구니를 기기/브라우저와 상관없이 유지하기 위한 테이블
// 같은 (회원, 상품) 줄이 중복되지 않는 것은 OrderingService.saveCart 가 저장 전에 합쳐서 보장한다
// (DB 유니크 제약은 물리 컬럼명 규칙에 따라 시작 오류가 날 수 있어 두지 않음)
@Entity
@NoArgsConstructor
@AllArgsConstructor
@Builder
@Getter
public class CartItem extends BaseTimeEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Long memberId;

    @Column(nullable = false)
    private Long productId;

    @Column(nullable = false)
    private Integer quantity;
}
