package com.example.ordersystem.ordering.service;

import com.amazonaws.services.sns.AmazonSNS;
import com.amazonaws.services.sns.AmazonSNSClientBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 주문/재고 알림을 SNS 로 보낸다 (SNS -> 이메일 구독).
 * - 인증: 키를 저장하지 않고 파드의 IAM 역할(IRSA)을 쓴다 (terraform/order_alerts.tf). 권한은 이 토픽에 Publish 만 가능.
 * - SNS_TOPIC_ARN 환경변수가 없으면 알림을 끈다(로컬 개발, 토픽이 없는 환경). 알림이 실패해도 주문은 절대 실패시키지 않는다.
 * - 주문 저장이 "커밋된 뒤에만" 보낸다. 롤백된 주문에 대해 "주문됨" 메일이 가지 않게 하기 위해서다.
 */
@Component
public class OrderNotifier {
    private static final Logger log = LoggerFactory.getLogger(OrderNotifier.class);

    // 남은 재고가 이 수량 이하이면 "재고 부족" 알림으로 보낸다 (관리자 요약의 재고 부족 기준(6 미만)과 같다)
    static final int LOW_STOCK_THRESHOLD = 5;

    private final String topicArn;
    private AmazonSNS sns;   // 첫 발행 때 만든다(시작 시 자격 증명 문제로 서비스가 죽지 않게)

    public OrderNotifier(@Value("${SNS_TOPIC_ARN:}") String topicArn) {
        this.topicArn = topicArn;
    }

    /** 주문 1건이 성공했을 때 호출. remainingStock = 이번 주문 반영 후 남은 재고 */
    public void orderPlaced(Long orderId, Long memberId, String productName, int quantity, int remainingStock) {
        boolean low = remainingStock <= LOW_STOCK_THRESHOLD;
        // SNS 제목은 ASCII 만 허용되므로 영문으로 쓰고, 본문(한글 가능)에 자세한 내용을 담는다
        String subject = (low ? "[NAM97 MALL] LOW STOCK - order #" : "[NAM97 MALL] New order #") + orderId;
        String body = "새 주문이 들어왔습니다.\n"
                + "- 주문 번호: " + orderId + "\n"
                + "- 회원 번호: " + memberId + "\n"
                + "- 상품: " + productName + "\n"
                + "- 수량: " + quantity + "\n"
                + "- 남은 재고: " + remainingStock + (low ? "  (재고 부족! 입고가 필요합니다)" : "");
        sendAfterCommit(subject, body);
    }

    private void sendAfterCommit(String subject, String body) {
        if (topicArn.isBlank()) return;
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() { publish(subject, body); }
            });
        } else {
            publish(subject, body);
        }
    }

    private void publish(String subject, String body) {
        try {
            if (sns == null) sns = AmazonSNSClientBuilder.defaultClient();   // 리전/자격 증명은 환경(AWS_REGION, IRSA)에서 읽는다
            sns.publish(topicArn, body, subject);
        } catch (Exception e) {
            // 알림 실패는 주문과 무관하다. 로그만 남긴다
            log.warn("주문 알림 발행 실패: {}", e.toString());
        }
    }
}
