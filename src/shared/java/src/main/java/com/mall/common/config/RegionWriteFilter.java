package com.mall.common.config;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

import org.springframework.stereotype.Component;

import jakarta.servlet.Filter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

@Component
public class RegionWriteFilter implements Filter {

    private final RegionConfig regionConfig;
    private final HttpClient httpClient;

    public RegionWriteFilter(RegionConfig regionConfig) {
        this.regionConfig = regionConfig;
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(5))
                .build();
    }

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {

        HttpServletRequest httpRequest = (HttpServletRequest) request;
        HttpServletResponse httpResponse = (HttpServletResponse) response;

        if (regionConfig.isPrimary() || isReadMethod(httpRequest.getMethod())) {
            chain.doFilter(request, response);
            return;
        }

        String primaryHost = regionConfig.getPrimaryHost();
        if (primaryHost == null || primaryHost.isBlank()) {
            chain.doFilter(request, response);
            return;
        }

        forwardToPrimary(httpRequest, httpResponse, primaryHost);
    }

    private boolean isReadMethod(String method) {
        return "GET".equalsIgnoreCase(method) || "HEAD".equalsIgnoreCase(method) || "OPTIONS".equalsIgnoreCase(method);
    }

    private void forwardToPrimary(HttpServletRequest req, HttpServletResponse resp, String primaryHost)
            throws IOException {
        String targetUrl = primaryHost + req.getRequestURI();
        if (req.getQueryString() != null) {
            targetUrl += "?" + req.getQueryString();
        }

        try {
            byte[] body = req.getInputStream().readAllBytes();
            HttpRequest.Builder builder = HttpRequest.newBuilder()
                    .uri(URI.create(targetUrl))
                    .header("X-Forwarded-From-Region", regionConfig.getAwsRegion())
                    .timeout(Duration.ofSeconds(30));

            builder = switch (req.getMethod().toUpperCase()) {
                case "POST" -> builder.POST(HttpRequest.BodyPublishers.ofByteArray(body));
                case "PUT" -> builder.PUT(HttpRequest.BodyPublishers.ofByteArray(body));
                case "DELETE" -> builder.DELETE();
                case "PATCH" -> builder.method("PATCH", HttpRequest.BodyPublishers.ofByteArray(body));
                default -> builder.GET();
            };

            HttpResponse<byte[]> primaryResp = httpClient.send(builder.build(),
                    HttpResponse.BodyHandlers.ofByteArray());

            resp.setStatus(primaryResp.statusCode());
            primaryResp.headers().map().forEach((k, v) ->
                    v.forEach(val -> resp.addHeader(k, val)));
            resp.getOutputStream().write(primaryResp.body());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            resp.sendError(502, "Forward to primary interrupted");
        }
    }
}
