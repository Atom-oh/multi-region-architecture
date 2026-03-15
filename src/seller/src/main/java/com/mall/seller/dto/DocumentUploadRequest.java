package com.mall.seller.dto;

public class DocumentUploadRequest {
    private String fileName;
    private String contentType;
    private String documentType;

    public DocumentUploadRequest() {}

    public DocumentUploadRequest(String fileName, String contentType, String documentType) {
        this.fileName = fileName;
        this.contentType = contentType;
        this.documentType = documentType;
    }

    public String getFileName() {
        return fileName;
    }

    public void setFileName(String fileName) {
        this.fileName = fileName;
    }

    public String getContentType() {
        return contentType;
    }

    public void setContentType(String contentType) {
        this.contentType = contentType;
    }

    public String getDocumentType() {
        return documentType;
    }

    public void setDocumentType(String documentType) {
        this.documentType = documentType;
    }
}
