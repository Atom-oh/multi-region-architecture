package com.mall.useraccount.service;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import com.mall.useraccount.dto.LoginRequest;
import com.mall.useraccount.dto.LoginResponse;
import com.mall.useraccount.dto.RegisterRequest;
import com.mall.useraccount.dto.UserResponse;
import com.mall.useraccount.event.UserEventPublisher;
import com.mall.useraccount.model.User;
import com.mall.useraccount.repository.UserRepository;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;

@Service
public class AuthService {

    private static final Logger logger = LoggerFactory.getLogger(AuthService.class);
    private static final long TOKEN_EXPIRATION_HOURS = 24;

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final SessionService sessionService;
    private final UserEventPublisher eventPublisher;
    private final String jwtSecret;

    public AuthService(
            UserRepository userRepository,
            PasswordEncoder passwordEncoder,
            SessionService sessionService,
            UserEventPublisher eventPublisher,
            @Value("${jwt.secret:default-secret-key-for-development-only-change-in-production}") String jwtSecret) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.sessionService = sessionService;
        this.eventPublisher = eventPublisher;
        this.jwtSecret = jwtSecret;
    }

    @Transactional
    public UserResponse register(RegisterRequest request) {
        if (userRepository.existsByEmail(request.email())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Email already registered");
        }

        User user = new User();
        user.setEmail(request.email());
        user.setPasswordHash(passwordEncoder.encode(request.password()));
        user.setName(request.name());
        user.setRole(User.Role.USER);
        user.setActive(true);

        user = userRepository.save(user);
        logger.info("User registered: {}", user.getId());

        eventPublisher.publishUserRegistered(user);

        return UserResponse.from(user);
    }

    @Transactional(readOnly = true)
    public LoginResponse login(LoginRequest request) {
        User user = userRepository.findByEmail(request.email())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid credentials"));

        if (!user.isActive()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Account is disabled");
        }

        if (!passwordEncoder.matches(request.password(), user.getPasswordHash())) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid credentials");
        }

        String token = generateToken(user);
        long expiresIn = TOKEN_EXPIRATION_HOURS * 3600;

        sessionService.createSession(user.getId().toString(), token);
        eventPublisher.publishUserLogin(user);

        logger.info("User logged in: {}", user.getId());

        return new LoginResponse(token, expiresIn, UserResponse.from(user));
    }

    public void logout(String userId) {
        sessionService.invalidateSession(userId);
        logger.info("User logged out: {}", userId);
    }

    @Transactional(readOnly = true)
    public UserResponse getCurrentUser(String userId) {
        User user = userRepository.findById(UUID.fromString(userId))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "User not found"));
        return UserResponse.from(user);
    }

    private String generateToken(User user) {
        Instant now = Instant.now();
        Instant expiration = now.plus(TOKEN_EXPIRATION_HOURS, ChronoUnit.HOURS);

        return Jwts.builder()
                .subject(user.getId().toString())
                .claim("email", user.getEmail())
                .claim("role", user.getRole().name())
                .issuedAt(Date.from(now))
                .expiration(Date.from(expiration))
                .signWith(Keys.hmacShaKeyFor(jwtSecret.getBytes()))
                .compact();
    }
}
