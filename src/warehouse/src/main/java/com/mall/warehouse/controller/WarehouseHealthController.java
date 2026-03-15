package com.mall.warehouse.controller;

import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

@Component
public class WarehouseHealthController {

    private final com.mall.common.health.HealthController healthController;

    public WarehouseHealthController(com.mall.common.health.HealthController healthController) {
        this.healthController = healthController;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void onApplicationReady() {
        healthController.setStarted(true);
        healthController.setReady(true);
    }
}
