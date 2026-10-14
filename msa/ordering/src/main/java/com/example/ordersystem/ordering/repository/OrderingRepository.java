package com.example.ordersystem.ordering.repository;

import com.example.ordersystem.ordering.domain.Ordering;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface OrderingRepository extends JpaRepository<Ordering, Long> {
    // 내 주문내역(최신순). 메서드 이름으로 쿼리가 자동 생성된다.
    List<Ordering> findByMemberIdOrderByIdDesc(Long memberId);
}
