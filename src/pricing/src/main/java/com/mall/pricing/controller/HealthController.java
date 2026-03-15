package com.mall.pricing.controller;

import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import com.mall.common.health.HealthController;

@Component
public class PricingHealthController {

    private final HealthController healthController;

    public PricingHealthController(HealthController healthController) {
        this.healthController = healthController;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void onApplicationReady() {
        healthController.setStarted(true);
        healthController.setReady(true);
    }
}
