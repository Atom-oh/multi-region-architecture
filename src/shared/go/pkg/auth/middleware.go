package auth

import (
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// Config holds the configuration for the auth middleware
type Config struct {
	UserPoolID string
	Region     string
	ClientID   string // Optional: if set, validates the audience claim
}

// jwksCache caches the JWKS keys with expiration
type jwksCache struct {
	mu        sync.RWMutex
	keys      map[string]*rsa.PublicKey
	expiresAt time.Time
}

var (
	cache    = &jwksCache{keys: make(map[string]*rsa.PublicKey)}
	cacheTTL = 1 * time.Hour
)

// JWKS represents the JSON Web Key Set response from Cognito
type JWKS struct {
	Keys []JWK `json:"keys"`
}

// JWK represents a single JSON Web Key
type JWK struct {
	Kid string `json:"kid"` // Key ID
	Kty string `json:"kty"` // Key type (RSA)
	Alg string `json:"alg"` // Algorithm (RS256)
	Use string `json:"use"` // Usage (sig)
	N   string `json:"n"`   // RSA modulus
	E   string `json:"e"`   // RSA exponent
}

// LoadConfigFromEnv loads auth configuration from environment variables.
// Returns nil config if COGNITO_USER_POOL_ID is not set (graceful degradation).
func LoadConfigFromEnv() *Config {
	userPoolID := os.Getenv("COGNITO_USER_POOL_ID")
	if userPoolID == "" {
		return nil
	}

	region := os.Getenv("COGNITO_REGION")
	if region == "" {
		region = os.Getenv("AWS_REGION")
	}
	if region == "" {
		region = "us-east-1"
	}

	clientID := os.Getenv("COGNITO_CLIENT_ID")

	return &Config{
		UserPoolID: userPoolID,
		Region:     region,
		ClientID:   clientID,
	}
}

// Middleware returns a Gin middleware that validates JWT tokens.
// If cfg is nil, the middleware skips authentication (graceful degradation for dev/test).
func Middleware(cfg *Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip auth if not configured (graceful degradation)
		if cfg == nil {
			c.Next()
			return
		}

		// Extract token from Authorization header
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error":   "unauthorized",
				"message": "missing Authorization header",
			})
			return
		}

		// Expect "Bearer <token>" format
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error":   "unauthorized",
				"message": "invalid Authorization header format, expected 'Bearer <token>'",
			})
			return
		}

		tokenString := parts[1]

		// Parse and validate the token
		claims, err := validateToken(tokenString, cfg)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error":   "unauthorized",
				"message": err.Error(),
			})
			return
		}

		// Store claims in context for downstream handlers
		SetClaims(c, claims)
		c.Next()
	}
}

// OptionalMiddleware validates JWT tokens if present, but doesn't require them.
// Useful for endpoints that work with or without authentication.
func OptionalMiddleware(cfg *Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip if not configured
		if cfg == nil {
			c.Next()
			return
		}

		// Check for Authorization header
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.Next()
			return
		}

		// Try to parse and validate
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) == 2 && strings.EqualFold(parts[0], "Bearer") {
			if claims, err := validateToken(parts[1], cfg); err == nil {
				SetClaims(c, claims)
			}
		}

		c.Next()
	}
}

// validateToken parses and validates a JWT token against Cognito JWKS
func validateToken(tokenString string, cfg *Config) (*Claims, error) {
	// Parse the token without validation first to get the key ID
	token, _, err := new(jwt.Parser).ParseUnverified(tokenString, jwt.MapClaims{})
	if err != nil {
		return nil, fmt.Errorf("invalid token format: %w", err)
	}

	// Get the key ID from the token header
	kid, ok := token.Header["kid"].(string)
	if !ok {
		return nil, fmt.Errorf("missing kid in token header")
	}

	// Get the public key for verification
	publicKey, err := getPublicKey(cfg, kid)
	if err != nil {
		return nil, fmt.Errorf("failed to get public key: %w", err)
	}

	// Parse and validate the token with the public key
	parsedToken, err := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
		// Verify signing algorithm
		if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return publicKey, nil
	}, jwt.WithValidMethods([]string{"RS256"}))

	if err != nil {
		return nil, fmt.Errorf("token validation failed: %w", err)
	}

	if !parsedToken.Valid {
		return nil, fmt.Errorf("invalid token")
	}

	// Extract claims
	mapClaims, ok := parsedToken.Claims.(jwt.MapClaims)
	if !ok {
		return nil, fmt.Errorf("invalid claims format")
	}

	// Validate issuer
	expectedIssuer := fmt.Sprintf("https://cognito-idp.%s.amazonaws.com/%s", cfg.Region, cfg.UserPoolID)
	if iss, _ := mapClaims["iss"].(string); iss != expectedIssuer {
		return nil, fmt.Errorf("invalid issuer: expected %s, got %s", expectedIssuer, iss)
	}

	// Validate audience (client_id) if configured
	if cfg.ClientID != "" {
		// For access tokens, check client_id claim
		// For id tokens, check aud claim
		clientID, _ := mapClaims["client_id"].(string)
		aud, _ := mapClaims["aud"].(string)
		if clientID != cfg.ClientID && aud != cfg.ClientID {
			return nil, fmt.Errorf("invalid audience")
		}
	}

	// Build Claims struct
	claims := &Claims{
		Issuer:   expectedIssuer,
		TokenUse: getString(mapClaims, "token_use"),
	}

	// Extract sub (user ID)
	claims.Sub = getString(mapClaims, "sub")

	// Extract email (may be in different claims depending on token type)
	claims.Email = getString(mapClaims, "email")
	if claims.Email == "" {
		claims.Email = getString(mapClaims, "username")
	}

	// Extract groups
	if groups, ok := mapClaims["cognito:groups"].([]interface{}); ok {
		for _, g := range groups {
			if gs, ok := g.(string); ok {
				claims.Groups = append(claims.Groups, gs)
			}
		}
	}

	// Extract timestamps
	if exp, ok := mapClaims["exp"].(float64); ok {
		claims.ExpiresAt = time.Unix(int64(exp), 0)
	}
	if iat, ok := mapClaims["iat"].(float64); ok {
		claims.IssuedAt = time.Unix(int64(iat), 0)
	}

	// Extract audience
	if aud, ok := mapClaims["aud"].(string); ok {
		claims.Audience = aud
	} else if clientID, ok := mapClaims["client_id"].(string); ok {
		claims.Audience = clientID
	}

	return claims, nil
}

// getPublicKey retrieves the RSA public key for the given key ID from JWKS
func getPublicKey(cfg *Config, kid string) (*rsa.PublicKey, error) {
	// Check cache first
	cache.mu.RLock()
	if time.Now().Before(cache.expiresAt) {
		if key, ok := cache.keys[kid]; ok {
			cache.mu.RUnlock()
			return key, nil
		}
	}
	cache.mu.RUnlock()

	// Fetch JWKS from Cognito
	jwksURL := fmt.Sprintf("https://cognito-idp.%s.amazonaws.com/%s/.well-known/jwks.json",
		cfg.Region, cfg.UserPoolID)

	resp, err := http.Get(jwksURL)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch JWKS: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("JWKS request failed with status %d", resp.StatusCode)
	}

	var jwks JWKS
	if err := json.NewDecoder(resp.Body).Decode(&jwks); err != nil {
		return nil, fmt.Errorf("failed to decode JWKS: %w", err)
	}

	// Update cache with new keys
	cache.mu.Lock()
	cache.keys = make(map[string]*rsa.PublicKey)
	cache.expiresAt = time.Now().Add(cacheTTL)

	var targetKey *rsa.PublicKey
	for _, key := range jwks.Keys {
		if key.Kty != "RSA" {
			continue
		}

		pubKey, err := jwkToRSAPublicKey(key)
		if err != nil {
			continue
		}

		cache.keys[key.Kid] = pubKey
		if key.Kid == kid {
			targetKey = pubKey
		}
	}
	cache.mu.Unlock()

	if targetKey == nil {
		return nil, fmt.Errorf("key ID %s not found in JWKS", kid)
	}

	return targetKey, nil
}

// jwkToRSAPublicKey converts a JWK to an RSA public key
func jwkToRSAPublicKey(jwk JWK) (*rsa.PublicKey, error) {
	// Decode the modulus (n)
	nBytes, err := base64.RawURLEncoding.DecodeString(jwk.N)
	if err != nil {
		return nil, fmt.Errorf("failed to decode modulus: %w", err)
	}
	n := new(big.Int).SetBytes(nBytes)

	// Decode the exponent (e)
	eBytes, err := base64.RawURLEncoding.DecodeString(jwk.E)
	if err != nil {
		return nil, fmt.Errorf("failed to decode exponent: %w", err)
	}
	// Convert exponent bytes to int
	var e int
	for _, b := range eBytes {
		e = e<<8 + int(b)
	}

	return &rsa.PublicKey{N: n, E: e}, nil
}

// getString safely extracts a string from map claims
func getString(claims jwt.MapClaims, key string) string {
	if v, ok := claims[key].(string); ok {
		return v
	}
	return ""
}
