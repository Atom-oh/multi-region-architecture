package com.mall.useraccount;

import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestController
public class Controller {

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

    @PostMapping("/api/v1/users/register")
    public Map<String, Object> register(@RequestBody Map<String, Object> user) {
        return Map.of(
            "id", "user-001",
            "email", user.getOrDefault("email", "user@example.com"),
            "username", user.getOrDefault("username", "newuser"),
            "status", "ACTIVE",
            "createdAt", "2026-03-20T10:00:00Z"
        );
    }

    @PostMapping("/api/v1/users/login")
    public Map<String, Object> login(@RequestBody Map<String, Object> credentials) {
        return Map.of(
            "userId", "user-001",
            "token", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.mock.token",
            "expiresAt", "2026-03-21T10:00:00Z"
        );
    }

    @GetMapping("/api/v1/users/{id}")
    public Map<String, Object> getUser(@PathVariable String id) {
        return Map.of(
            "id", id,
            "email", "user@example.com",
            "username", "johndoe",
            "firstName", "John",
            "lastName", "Doe",
            "status", "ACTIVE",
            "createdAt", "2026-01-15T08:30:00Z"
        );
    }

    @PutMapping("/api/v1/users/{id}")
    public Map<String, Object> updateUser(@PathVariable String id, @RequestBody Map<String, Object> user) {
        return Map.of(
            "id", id,
            "email", user.getOrDefault("email", "user@example.com"),
            "username", user.getOrDefault("username", "johndoe"),
            "firstName", user.getOrDefault("firstName", "John"),
            "lastName", user.getOrDefault("lastName", "Doe"),
            "status", "ACTIVE",
            "updatedAt", "2026-03-20T10:00:00Z"
        );
    }
}
