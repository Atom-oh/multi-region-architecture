package com.mall.payment.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;

import com.mall.common.config.AuroraConfig;
import com.mall.common.config.KafkaConfig;
import com.mall.common.config.RegionConfig;
import com.mall.common.config.ValkeyConfig;

@Configuration
@Import({RegionConfig.class, AuroraConfig.class, ValkeyConfig.class, KafkaConfig.class})
public class PaymentConfig {
}
