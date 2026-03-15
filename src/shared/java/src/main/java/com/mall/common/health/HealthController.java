package com.mall.common.health;

import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/health")
public class HealthController {

    private final AtomicBoolean ready = new AtomicBoolean(false);
    private final AtomicBoolean started = new AtomicBoolean(false);

    public void setReady(boolean isReady) {
        this.ready.set(isReady);
    }

    public void setStarted(boolean isStarted) {
        this.started.set(isStarted);
    }

    @GetMapping("/ready")
    public ResponseEntity<Map<String, String>> readiness() {
        if (ready.get()) {
            return ResponseEntity.ok(Map.of("status", "ready"));
        }
        return ResponseEntity.status(503).body(Map.of("status", "not_ready"));
    }

    @GetMapping("/live")
    public ResponseEntity<Map<String, String>> liveness() {
        return ResponseEntity.ok(Map.of("status", "alive"));
    }

    @GetMapping("/startup")
    public ResponseEntity<Map<String, String>> startup() {
        if (started.get()) {
            return ResponseEntity.ok(Map.of("status", "started"));
        }
        return ResponseEntity.status(503).body(Map.of("status", "starting"));
    }
}
