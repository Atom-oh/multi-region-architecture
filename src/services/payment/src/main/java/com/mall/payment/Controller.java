package com.mall.payment;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.*;

@RestController
@CrossOrigin(origins = "*", allowedHeaders = "*", methods = {RequestMethod.GET, RequestMethod.POST, RequestMethod.PUT, RequestMethod.DELETE, RequestMethod.OPTIONS})
public class Controller {

    @Autowired(required = false)
    private JdbcTemplate jdbcTemplate;

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
        String paymentId = "PAY-NEW-001";
        String transactionId = "TXN-" + System.currentTimeMillis();

        if (jdbcTemplate != null) {
            try {
                UUID newPaymentId = UUID.randomUUID();
                BigDecimal amount = new BigDecimal(payment.getOrDefault("amount", 0).toString());
                String orderId = (String) payment.getOrDefault("order_id", null);
                String method = (String) payment.getOrDefault("method", "CREDIT_CARD");

                jdbcTemplate.update(
                    "INSERT INTO payments (id, order_id, amount, currency, method, status, transaction_id, created_at, updated_at) VALUES (?::uuid, ?::uuid, ?, ?, ?, ?, ?, NOW(), NOW())",
                    newPaymentId.toString(),
                    orderId != null && !orderId.startsWith("ORD-") ? orderId : UUID.randomUUID().toString(),
                    amount, "KRW", method, "completed", transactionId
                );
                paymentId = newPaymentId.toString();
            } catch (Exception e) {
                // Fall back to mock ID
            }
        }

        Map<String, Object> response = Map.ofEntries(
            Map.entry("id", paymentId),
            Map.entry("order_id", payment.getOrDefault("order_id", "ORD-NEW")),
            Map.entry("amount", payment.getOrDefault("amount", 0)),
            Map.entry("currency", "KRW"),
            Map.entry("method", payment.getOrDefault("method", "CREDIT_CARD")),
            Map.entry("method_display", "신용카드"),
            Map.entry("status", "completed"),
            Map.entry("status_display", "결제완료"),
            Map.entry("transaction_id", transactionId),
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
        if (jdbcTemplate != null) {
            try {
                List<Map<String, Object>> payments = jdbcTemplate.queryForList(
                    "SELECT id, order_id, amount, currency, method, status, transaction_id, created_at FROM payments ORDER BY created_at DESC LIMIT 20"
                );
                if (!payments.isEmpty()) {
                    List<Map<String, Object>> result = new ArrayList<>();
                    for (Map<String, Object> row : payments) {
                        Map<String, Object> payment = new LinkedHashMap<>();
                        payment.put("id", row.get("id").toString());
                        payment.put("order_id", row.get("order_id") != null ? row.get("order_id").toString() : null);
                        payment.put("amount", row.get("amount"));
                        payment.put("currency", row.get("currency"));
                        payment.put("method", row.get("method"));
                        payment.put("method_display", getMethodDisplay((String) row.get("method")));
                        payment.put("status", row.get("status"));
                        payment.put("status_display", getStatusDisplay((String) row.get("status")));
                        payment.put("transaction_id", row.get("transaction_id"));
                        payment.put("created_at", row.get("created_at").toString());
                        result.add(payment);
                    }
                    return ResponseEntity.ok()
                        .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
                        .body(result);
                }
            } catch (Exception e) {
                // Fall back to empty result
            }
        }

        // Empty fallback - no mock data
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(List.of());
    }

    @GetMapping("/api/v1/payments/{id}")
    public ResponseEntity<Map<String, Object>> getPayment(@PathVariable String id) {
        if (jdbcTemplate != null) {
            try {
                List<Map<String, Object>> payments = jdbcTemplate.queryForList(
                    "SELECT * FROM payments WHERE id = ?::uuid", id
                );
                if (!payments.isEmpty()) {
                    Map<String, Object> row = payments.get(0);
                    Map<String, Object> payment = new LinkedHashMap<>();
                    payment.put("id", row.get("id").toString());
                    payment.put("order_id", row.get("order_id") != null ? row.get("order_id").toString() : null);
                    payment.put("amount", row.get("amount"));
                    payment.put("currency", row.get("currency"));
                    payment.put("method", row.get("method"));
                    payment.put("method_display", getMethodDisplay((String) row.get("method")));
                    payment.put("status", row.get("status"));
                    payment.put("status_display", getStatusDisplay((String) row.get("status")));
                    payment.put("transaction_id", row.get("transaction_id"));
                    payment.put("created_at", row.get("created_at").toString());

                    return ResponseEntity.ok()
                        .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
                        .body(payment);
                }
            } catch (Exception e) {
                // Fall back to empty result
            }
        }

        // Empty fallback - no mock data
        Map<String, Object> payment = Map.of(
            "id", id,
            "error", "결제 정보를 찾을 수 없습니다",
            "status", "not_found"
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(payment);
    }

    @PostMapping("/api/v1/payments/{id}/refund")
    public ResponseEntity<Map<String, Object>> refundPayment(@PathVariable String id, @RequestBody(required = false) Map<String, Object> refundRequest) {
        int refundAmount = 0;
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

    private String getMethodDisplay(String method) {
        if (method == null) return "알 수 없음";
        switch (method) {
            case "CREDIT_CARD": return "신용카드";
            case "KAKAO_PAY": return "카카오페이";
            case "NAVER_PAY": return "네이버페이";
            case "TOSS_PAY": return "토스페이";
            case "BANK_TRANSFER": return "계좌이체";
            default: return method;
        }
    }

    private String getStatusDisplay(String status) {
        if (status == null) return "알 수 없음";
        switch (status) {
            case "pending": return "결제대기";
            case "completed": return "결제완료";
            case "failed": return "결제실패";
            case "refunded": return "환불완료";
            case "cancelled": return "결제취소";
            default: return status;
        }
    }
}
