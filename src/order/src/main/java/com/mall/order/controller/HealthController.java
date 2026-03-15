package com.mall.order.controller;

import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import com.mall.common.health.HealthController;

@Component
public class OrderHealthController extends HealthController {

    @EventListener(ApplicationReadyEvent.class)
    public void onApplicationReady() {
        setStarted(true);
        setReady(true);
    }
}
