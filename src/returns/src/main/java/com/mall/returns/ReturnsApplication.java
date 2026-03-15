package com.mall.returns;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.ComponentScan;

@SpringBootApplication
@ComponentScan(basePackages = {"com.mall.returns", "com.mall.common"})
public class ReturnsApplication {

    public static void main(String[] args) {
        SpringApplication.run(ReturnsApplication.class, args);
    }
}
