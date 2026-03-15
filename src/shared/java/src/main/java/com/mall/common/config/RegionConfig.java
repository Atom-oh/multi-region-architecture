package com.mall.common.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;

@Configuration
public class RegionConfig {

    @Value("${region.role:PRIMARY}")
    private String regionRole;

    @Value("${region.aws-region:us-east-1}")
    private String awsRegion;

    @Value("${region.primary-host:}")
    private String primaryHost;

    public boolean isPrimary() {
        return "PRIMARY".equalsIgnoreCase(regionRole);
    }

    public String getRegionRole() {
        return regionRole;
    }

    public String getAwsRegion() {
        return awsRegion;
    }

    public String getPrimaryHost() {
        return primaryHost;
    }
}
