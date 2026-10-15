package com.example.ordersystem.ordering.repository;

import com.example.ordersystem.ordering.domain.CartItem;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface CartItemRepository extends JpaRepository<CartItem, Long> {
    List<CartItem> findByMemberId(Long memberId);

    // 장바구니 전체 교체(저장)용: 해당 회원의 기존 줄을 모두 지운다
    void deleteByMemberId(Long memberId);
}
