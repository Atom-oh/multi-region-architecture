<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# user-account/

## Purpose
Java Spring Boot authentication and user account service handling registration, login, JWT tokens, and session management with Valkey for distributed sessions.

## Key Files
| File | Description |
|------|-------------|
| `pom.xml` | Maven dependencies |
| `Dockerfile` | Container build definition |
| `src/main/java/com/mall/useraccount/UserAccountApplication.java` | Spring Boot entry |
| `src/main/java/com/mall/useraccount/controller/AuthController.java` | Auth endpoints |
| `src/main/java/com/mall/useraccount/service/AuthService.java` | Authentication logic |
| `src/main/java/com/mall/useraccount/service/SessionService.java` | Session management |
| `src/main/java/com/mall/useraccount/config/SecurityConfig.java` | Spring Security config |
| `src/main/java/com/mall/useraccount/model/User.java` | User JPA entity |
| `src/main/java/com/mall/useraccount/event/UserEventPublisher.java` | Kafka publisher |
| `src/main/resources/application.yml` | Spring configuration |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `src/main/java/com/mall/useraccount/config/` | Security configurations |
| `src/main/java/com/mall/useraccount/controller/` | REST controllers |
| `src/main/java/com/mall/useraccount/dto/` | Request/response DTOs |
| `src/main/java/com/mall/useraccount/event/` | Kafka event publishing |
| `src/main/java/com/mall/useraccount/model/` | JPA entities |
| `src/main/java/com/mall/useraccount/repository/` | Data repositories |
| `src/main/java/com/mall/useraccount/service/` | Business services |

## For AI Agents

### Working In This Directory
- Uses Spring Security with JWT authentication
- Sessions stored in Valkey for cross-region access
- Publishes user.registered, user.login events

### Common Patterns
```java
// JWT token generation
@Service
public class AuthService {
    public String generateToken(User user) {
        // JWT creation with claims
    }
}
```

## Dependencies
### Internal
- `shared/java` mall-common library
### External
- Spring Boot 3.2.2
- Spring Security
- jjwt (JWT library)

<!-- MANUAL: -->
