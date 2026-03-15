package com.mall.seller.service;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.mall.seller.dto.DocumentUploadRequest;
import com.mall.seller.dto.DocumentUploadResponse;

import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.PresignedPutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;

@Service
public class S3Service {

    private static final Logger logger = LoggerFactory.getLogger(S3Service.class);
    private static final Duration PRESIGNED_URL_DURATION = Duration.ofMinutes(15);

    @Value("${aws.s3.bucket:mall-seller-documents}")
    private String bucket;

    private final S3Presigner presigner;

    public S3Service() {
        this.presigner = S3Presigner.create();
    }

    public DocumentUploadResponse generatePresignedUploadUrl(UUID sellerId, DocumentUploadRequest request) {
        String documentId = UUID.randomUUID().toString();
        String key = String.format("sellers/%s/%s/%s", sellerId, request.getDocumentType(), documentId);

        PutObjectRequest objectRequest = PutObjectRequest.builder()
                .bucket(bucket)
                .key(key)
                .contentType(request.getContentType())
                .build();

        PutObjectPresignRequest presignRequest = PutObjectPresignRequest.builder()
                .signatureDuration(PRESIGNED_URL_DURATION)
                .putObjectRequest(objectRequest)
                .build();

        PresignedPutObjectRequest presignedRequest = presigner.presignPutObject(presignRequest);
        String uploadUrl = presignedRequest.url().toString();

        LocalDateTime expiresAt = LocalDateTime.now().plus(PRESIGNED_URL_DURATION);

        logger.info("Generated presigned URL for seller {} document {}", sellerId, documentId);

        return new DocumentUploadResponse(documentId, uploadUrl, key, expiresAt);
    }
}
