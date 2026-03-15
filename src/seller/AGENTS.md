<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# seller/

## Purpose
Java Spring Boot seller portal service managing seller registration, product listings, document uploads to S3, and seller analytics. Supports multi-tenant seller operations.

## Key Files
| File | Description |
|------|-------------|
| `pom.xml` | Maven dependencies |
| `Dockerfile` | Container build definition |
| `src/main/java/com/mall/seller/SellerApplication.java` | Spring Boot entry |
| `src/main/java/com/mall/seller/controller/SellerController.java` | REST endpoints |
| `src/main/java/com/mall/seller/service/SellerService.java` | Seller logic |
| `src/main/java/com/mall/seller/service/S3Service.java` | S3 file operations |
| `src/main/java/com/mall/seller/model/Seller.java` | Seller entity |
| `src/main/java/com/mall/seller/model/SellerProduct.java` | Seller product entity |
| `src/main/resources/application.yml` | Spring configuration |
| `src/main/resources/db/migration/V1__init.sql` | Flyway migration |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `src/main/java/com/mall/seller/controller/` | REST controllers |
| `src/main/java/com/mall/seller/dto/` | Request/response DTOs |
| `src/main/java/com/mall/seller/model/` | JPA entities |
| `src/main/java/com/mall/seller/repository/` | Data repositories |
| `src/main/java/com/mall/seller/service/` | Business services |

## For AI Agents

### Working In This Directory
- Seller documents stored in S3 with presigned URLs
- Product listings sync to product-catalog service
- Supports seller verification workflow

### Common Patterns
```java
// S3 presigned URL generation
public String generateUploadUrl(String sellerId, String fileName) {
    return s3Service.generatePresignedUrl(
        bucketName,
        "sellers/" + sellerId + "/" + fileName
    );
}
```

## Dependencies
### Internal
- `shared/java` mall-common library
### External
- Spring Boot 3.2.2
- Spring Data JPA
- AWS SDK v2 (S3)

<!-- MANUAL: -->
