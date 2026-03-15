package com.mall.seller.dto;

import java.time.LocalDateTime;

public class DocumentUploadResponse {
    private String documentId;
    private String uploadUrl;
    private String key;
    private LocalDateTime expiresAt;

    public DocumentUploadResponse() {}

    public DocumentUploadResponse(String documentId, String uploadUrl, String key, LocalDateTime expiresAt) {
        this.documentId = documentId;
        this.uploadUrl = uploadUrl;
        this.key = key;
        this.expiresAt = expiresAt;
    }

    public String getDocumentId() {
        return documentId;
    }

    public void setDocumentId(String documentId) {
        this.documentId = documentId;
    }

    public String getUploadUrl() {
        return uploadUrl;
    }

    public void setUploadUrl(String uploadUrl) {
        this.uploadUrl = uploadUrl;
    }

    public String getKey() {
        return key;
    }

    public void setKey(String key) {
        this.key = key;
    }

    public LocalDateTime getExpiresAt() {
        return expiresAt;
    }

    public void setExpiresAt(LocalDateTime expiresAt) {
        this.expiresAt = expiresAt;
    }
}
