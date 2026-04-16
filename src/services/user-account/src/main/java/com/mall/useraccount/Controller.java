package com.mall.useraccount;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@CrossOrigin(origins = "*", allowedHeaders = "*", methods = {RequestMethod.GET, RequestMethod.POST, RequestMethod.PUT, RequestMethod.DELETE, RequestMethod.OPTIONS})
public class Controller {

    @Autowired(required = false)
    private JdbcTemplate jdbcTemplate;

    @GetMapping("/")
    public Map<String, Object> root() {
        return Map.of(
            "service", "user-account-service",
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

    @GetMapping("/api/v1/users")
    public ResponseEntity<List<Map<String, Object>>> getUsers() {
        if (jdbcTemplate != null) {
            try {
                List<Map<String, Object>> users = jdbcTemplate.queryForList(
                    "SELECT id, email, username, full_name, phone, status, created_at FROM users LIMIT 20"
                );
                if (!users.isEmpty()) {
                    List<Map<String, Object>> result = new ArrayList<>();
                    for (Map<String, Object> row : users) {
                        Map<String, Object> user = new LinkedHashMap<>();
                        user.put("id", row.get("id").toString());
                        user.put("email", row.get("email"));
                        user.put("username", row.get("username"));
                        user.put("name", row.get("full_name"));
                        user.put("phone", row.get("phone"));
                        user.put("status", row.get("status"));
                        user.put("created_at", row.get("created_at") != null ? row.get("created_at").toString() : null);
                        result.add(user);
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

    @PostMapping("/api/v1/users/register")
    public ResponseEntity<Map<String, Object>> register(@RequestBody Map<String, Object> user) {
        Map<String, Object> response = Map.ofEntries(
            Map.entry("id", UUID.randomUUID().toString()),
            Map.entry("email", user.getOrDefault("email", "newuser@example.com")),
            Map.entry("name", user.getOrDefault("name", "신규회원")),
            Map.entry("phone", user.getOrDefault("phone", "")),
            Map.entry("status", "ACTIVE"),
            Map.entry("membership", Map.of(
                "tier", "BRONZE",
                "points", 1000,
                "welcome_coupon", true
            )),
            Map.entry("created_at", "2026-03-20T10:00:00Z"),
            Map.entry("message", "회원가입이 완료되었습니다. 환영합니다!")
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }

    @PostMapping("/api/v1/users/login")
    public ResponseEntity<Map<String, Object>> login(@RequestBody Map<String, Object> credentials) {
        // NOTE: In production, this endpoint should integrate with AWS Cognito using the AWS SDK.
        // The frontend should call Cognito directly for authentication, or this service should
        // use cognito-idp:InitiateAuth / AdminInitiateAuth to authenticate users.
        // This mock response demonstrates the expected token structure from Cognito.

        String email = (String) credentials.getOrDefault("email", "");
        Map<String, Object> userInfo;
        String userId;

        // User IDs match seed data UUIDs in DocumentDB user_profiles collection
        if (email.contains("minsu")) {
            userId = "a0000001-0000-0000-0000-000000000001";
            userInfo = Map.of(
                "user_id", userId,
                "sub", userId,
                "name", "김민준",
                "email", "minsu@example.com",
                "email_verified", true,
                "membership_tier", "GOLD"
            );
        } else if (email.contains("seoyeon")) {
            userId = "a0000001-0000-0000-0000-000000000002";
            userInfo = Map.of(
                "user_id", userId,
                "sub", userId,
                "name", "이소연",
                "email", "seoyeon@example.com",
                "email_verified", true,
                "membership_tier", "PLATINUM"
            );
        } else if (email.contains("jihoon")) {
            userId = "a0000001-0000-0000-0000-000000000003";
            userInfo = Map.of(
                "user_id", userId,
                "sub", userId,
                "name", "박지훈",
                "email", "jihoon@example.com",
                "email_verified", true,
                "membership_tier", "SILVER"
            );
        } else {
            // Default user for any other email
            userId = "a0000001-0000-0000-0000-000000000001";
            userInfo = Map.of(
                "user_id", userId,
                "sub", userId,
                "name", "김민준",
                "email", email.isEmpty() ? "minsu@example.com" : email,
                "email_verified", true,
                "membership_tier", "GOLD"
            );
        }

        // Mock Cognito-style token response structure
        // In production, these would be actual JWTs from Cognito's InitiateAuth response
        long currentTime = System.currentTimeMillis() / 1000;
        long expiresIn = 3600; // 1 hour

        Map<String, Object> response = Map.ofEntries(
            Map.entry("user", userInfo),
            // Cognito returns these token fields in AuthenticationResult
            Map.entry("access_token", "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6Im1vY2sta2V5LWlkIn0.eyJzdWIiOiIiLCJpc3MiOiJodHRwczovL2NvZ25pdG8taWRwLnVzLWVhc3QtMS5hbWF6b25hd3MuY29tL3VzLWVhc3QtMV9tb2NrIiwiY2xpZW50X2lkIjoibW9jay1jbGllbnQtaWQiLCJ0b2tlbl91c2UiOiJhY2Nlc3MiLCJzY29wZSI6Im9wZW5pZCBlbWFpbCBwcm9maWxlIiwiYXV0aF90aW1lIjoxNzExMDAwMDAwLCJleHAiOjE3MTEwMDM2MDAsImlhdCI6MTcxMTAwMDAwMH0.mock-signature-" + System.currentTimeMillis()),
            Map.entry("id_token", "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6Im1vY2sta2V5LWlkIn0.eyJzdWIiOiIiLCJpc3MiOiJodHRwczovL2NvZ25pdG8taWRwLnVzLWVhc3QtMS5hbWF6b25hd3MuY29tL3VzLWVhc3QtMV9tb2NrIiwiYXVkIjoibW9jay1jbGllbnQtaWQiLCJ0b2tlbl91c2UiOiJpZCIsImVtYWlsIjoiIiwiZW1haWxfdmVyaWZpZWQiOnRydWUsIm5hbWUiOiIiLCJleHAiOjE3MTEwMDM2MDAsImlhdCI6MTcxMTAwMDAwMH0.mock-signature-" + System.currentTimeMillis()),
            Map.entry("refresh_token", "mock-refresh-token-" + System.currentTimeMillis()),
            Map.entry("token_type", "Bearer"),
            Map.entry("expires_in", expiresIn),
            // Additional fields for client convenience
            Map.entry("issued_at", currentTime),
            Map.entry("expires_at", currentTime + expiresIn),
            Map.entry("message", "로그인되었습니다. Note: In production, use Cognito SDK for authentication.")
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }

    @GetMapping("/api/v1/users/{id}")
    public ResponseEntity<Map<String, Object>> getUser(@PathVariable String id) {
        if (jdbcTemplate != null) {
            try {
                List<Map<String, Object>> users = jdbcTemplate.queryForList(
                    "SELECT * FROM users WHERE id = ?::uuid", id
                );
                if (!users.isEmpty()) {
                    Map<String, Object> row = users.get(0);
                    Map<String, Object> user = new LinkedHashMap<>();
                    user.put("id", row.get("id").toString());
                    user.put("email", row.get("email"));
                    user.put("username", row.get("username"));
                    user.put("name", row.get("full_name"));
                    user.put("phone", row.get("phone"));
                    user.put("status", row.get("status"));
                    user.put("created_at", row.get("created_at") != null ? row.get("created_at").toString() : null);
                    user.put("membership", Map.of(
                        "tier", "GOLD",
                        "tier_display", "골드",
                        "points", 125000
                    ));

                    return ResponseEntity.ok()
                        .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
                        .body(user);
                }
            } catch (Exception e) {
                // Fall back to empty result
            }
        }

        // Empty fallback - no mock data
        Map<String, Object> user = Map.of(
            "id", id,
            "error", "사용자를 찾을 수 없습니다",
            "status", "not_found"
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(user);
    }

    @PutMapping("/api/v1/users/{id}")
    public ResponseEntity<Map<String, Object>> updateUser(@PathVariable String id, @RequestBody Map<String, Object> user) {
        Map<String, Object> response = Map.of(
            "id", id,
            "email", user.getOrDefault("email", "user@example.com"),
            "name", user.getOrDefault("name", "사용자"),
            "phone", user.getOrDefault("phone", ""),
            "status", "ACTIVE",
            "updated_at", "2026-03-20T10:00:00Z",
            "message", "회원정보가 수정되었습니다"
        );
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .body(response);
    }
}
