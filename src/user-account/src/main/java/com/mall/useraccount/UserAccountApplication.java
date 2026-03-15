package com.mall.useraccount;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.ComponentScan;

@SpringBootApplication
@ComponentScan(basePackages = {"com.mall.useraccount", "com.mall.common"})
public class UserAccountApplication {

    public static void main(String[] args) {
        SpringApplication.run(UserAccountApplication.class, args);
    }
}
