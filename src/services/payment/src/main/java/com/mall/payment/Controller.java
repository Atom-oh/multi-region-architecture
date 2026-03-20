package com.mall.payment;

import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@CrossOrigin(origins = "*", allowedHeaders = "*", methods = {RequestMethod.GET, RequestMethod.POST, RequestMethod.PUT, RequestMethod.DELETE, RequestMethod.OPTIONS})
public class Controller {

    @GetMapping("/")
    public Map<String, Object> root() {
        return Map.of(
            "service", "payment-service",
            "version", "1.0.0",
            "status", "running"
        );
    }

    @GetMapping("/health/ready")
    public Map<String, String> ready() {
        return Map.of("status", "ready");
    }

    @GetMapping("/health/live")
    public Map<String, String> live() {
        return Map.of("status", "alive");
    }

    @GetMapping("/health/startup")
    public Map<String, String> startup() {
        return Map.of("status", "started");
    }

    @PostMapping("/api/v1/payments")
    public ResponseEntity<Map<String, Object>> createPayment(@RequestBody Map<String, Object> payment) {
        Map<String, Object> response = Map.ofEntries(
            Map.entry("id", "PAY-NEW-001"),
            Map.entry("order_id", payment.getOrDefault("order_id", "ORD-NEW")),
            Map.entry("amount", payment.getOrDefault("amount", 0)),
            Map.entry("currency", "KRW"),
            Map.entry("method", payment.getOrDefault("method", "CREDIT_CARD")),
            Map.entry("method_display", "신용카드"),
            Map.entry("status", "completed"),
            Map.entry("status_display", "결제완료"),
            Map.entry("transaction_id", "TXN-" + System.currentTimeMillis()),
            Map.entry("pg_provider", "토스페이먼츠"),
            Map.entry("created_at", "2026-03-20T10:05:00Z"),
            Map.entry("message", "결제가 완료되었습니다")
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }

    @GetMapping("/api/v1/payments")
    public ResponseEntity<List<Map<String, Object>>> getPayments() {
        List<Map<String, Object>> payments = List.of(
            Map.ofEntries(
                Map.entry("id", "PAY-001"),
                Map.entry("order_id", "ORD-001"),
                Map.entry("user_id", "USR-001"),
                Map.entry("amount", 2319000),
                Map.entry("currency", "KRW"),
                Map.entry("method", "CREDIT_CARD"),
                Map.entry("method_display", "신용카드 (삼성)"),
                Map.entry("status", "completed"),
                Map.entry("status_display", "결제완료"),
                Map.entry("created_at", "2026-03-15T14:32:00Z")
            ),
            Map.ofEntries(
                Map.entry("id", "PAY-002"),
                Map.entry("order_id", "ORD-002"),
                Map.entry("user_id", "USR-002"),
                Map.entry("amount", 699000),
                Map.entry("currency", "KRW"),
                Map.entry("method", "KAKAO_PAY"),
                Map.entry("method_display", "카카오페이"),
                Map.entry("status", "completed"),
                Map.entry("status_display", "결제완료"),
                Map.entry("created_at", "2026-03-18T11:22:00Z")
            ),
            Map.ofEntries(
                Map.entry("id", "PAY-003"),
                Map.entry("order_id", "ORD-003"),
                Map.entry("user_id", "USR-003"),
                Map.entry("amount", 218000),
                Map.entry("currency", "KRW"),
                Map.entry("method", "NAVER_PAY"),
                Map.entry("method_display", "네이버페이"),
                Map.entry("status", "completed"),
                Map.entry("status_display", "결제완료"),
                Map.entry("created_at", "2026-03-20T09:47:00Z")
            )
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(payments);
    }

    @GetMapping("/api/v1/payments/{id}")
    public ResponseEntity<Map<String, Object>> getPayment(@PathVariable String id) {
        Map<String, Object> payment;
        switch (id) {
            case "PAY-001":
                payment = Map.ofEntries(
                    Map.entry("id", "PAY-001"),
                    Map.entry("order_id", "ORD-001"),
                    Map.entry("user_id", "USR-001"),
                    Map.entry("user_name", "김민수"),
                    Map.entry("amount", 2319000),
                    Map.entry("currency", "KRW"),
                    Map.entry("method", "CREDIT_CARD"),
                    Map.entry("method_display", "신용카드"),
                    Map.entry("card_info", Map.of(
                        "issuer", "삼성카드",
                        "number", "****-****-****-1234",
                        "installment", "일시불"
                    )),
                    Map.entry("status", "completed"),
                    Map.entry("status_display", "결제완료"),
                    Map.entry("transaction_id", "TXN-20260315143200001"),
                    Map.entry("pg_provider", "토스페이먼츠"),
                    Map.entry("created_at", "2026-03-15T14:32:00Z"),
                    Map.entry("receipt_url", "https://receipt.example.com/PAY-001")
                );
                break;
            case "PAY-002":
                payment = Map.ofEntries(
                    Map.entry("id", "PAY-002"),
                    Map.entry("order_id", "ORD-002"),
                    Map.entry("user_id", "USR-002"),
                    Map.entry("user_name", "이서연"),
                    Map.entry("amount", 699000),
                    Map.entry("currency", "KRW"),
                    Map.entry("method", "KAKAO_PAY"),
                    Map.entry("method_display", "카카오페이"),
                    Map.entry("status", "completed"),
                    Map.entry("status_display", "결제완료"),
                    Map.entry("transaction_id", "TXN-20260318112200002"),
                    Map.entry("pg_provider", "카카오페이"),
                    Map.entry("created_at", "2026-03-18T11:22:00Z"),
                    Map.entry("receipt_url", "https://receipt.example.com/PAY-002")
                );
                break;
            case "PAY-003":
                payment = Map.ofEntries(
                    Map.entry("id", "PAY-003"),
                    Map.entry("order_id", "ORD-003"),
                    Map.entry("user_id", "USR-003"),
                    Map.entry("user_name", "박지훈"),
                    Map.entry("amount", 218000),
                    Map.entry("currency", "KRW"),
                    Map.entry("method", "NAVER_PAY"),
                    Map.entry("method_display", "네이버페이"),
                    Map.entry("status", "completed"),
                    Map.entry("status_display", "결제완료"),
                    Map.entry("transaction_id", "TXN-20260320094700003"),
                    Map.entry("pg_provider", "네이버페이"),
                    Map.entry("created_at", "2026-03-20T09:47:00Z"),
                    Map.entry("receipt_url", "https://receipt.example.com/PAY-003")
                );
                break;
            default:
                payment = Map.of(
                    "id", id,
                    "error", "결제 정보를 찾을 수 없습니다",
                    "status", "not_found"
                );
        }
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(payment);
    }

    @PostMapping("/api/v1/payments/{id}/refund")
    public ResponseEntity<Map<String, Object>> refundPayment(@PathVariable String id, @RequestBody(required = false) Map<String, Object> refundRequest) {
        int refundAmount = 0;
        switch (id) {
            case "PAY-001": refundAmount = 2319000; break;
            case "PAY-002": refundAmount = 699000; break;
            case "PAY-003": refundAmount = 218000; break;
            default: refundAmount = 0;
        }

        if (refundRequest != null && refundRequest.containsKey("amount")) {
            refundAmount = ((Number) refundRequest.get("amount")).intValue();
        }

        Map<String, Object> response = Map.ofEntries(
            Map.entry("id", id),
            Map.entry("refund_id", "REF-" + System.currentTimeMillis()),
            Map.entry("amount", refundAmount),
            Map.entry("currency", "KRW"),
            Map.entry("status", "refunded"),
            Map.entry("status_display", "환불완료"),
            Map.entry("reason", refundRequest != null ? refundRequest.getOrDefault("reason", "고객 요청") : "고객 요청"),
            Map.entry("refunded_at", "2026-03-20T12:00:00Z"),
            Map.entry("message", "환불이 완료되었습니다. 카드사에 따라 영업일 기준 3-5일 내 환불됩니다.")
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }
}
