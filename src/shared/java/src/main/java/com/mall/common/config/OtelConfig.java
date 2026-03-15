package com.mall.common.config;

import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import org.slf4j.MDC;
import org.springframework.boot.autoconfigure.condition.ConditionalOnClass;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import jakarta.servlet.Filter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletResponse;

@Configuration
@ConditionalOnClass(OpenTelemetry.class)
public class OtelConfig {

    @Bean
    public Tracer tracer() {
        return GlobalOpenTelemetry.getTracer("mall-common");
    }

    @Bean
    public Filter traceIdMdcFilter() {
        return (ServletRequest request, ServletResponse response, FilterChain chain) -> {
            Span span = Span.current();
            if (span.getSpanContext().isValid()) {
                MDC.put("trace_id", span.getSpanContext().getTraceId());
                MDC.put("span_id", span.getSpanContext().getSpanId());
            }
            try {
                chain.doFilter(request, response);
            } finally {
                MDC.remove("trace_id");
                MDC.remove("span_id");
            }
        };
    }
}
