package auth

import (
	"time"

	"github.com/gin-gonic/gin"
)

// Claims represents the JWT claims extracted from a Cognito token
type Claims struct {
	Sub       string    `json:"sub"`        // User ID (Cognito UUID)
	Email     string    `json:"email"`      // User email
	Groups    []string  `json:"groups"`     // Cognito groups
	ExpiresAt time.Time `json:"expires_at"` // Token expiration time
	IssuedAt  time.Time `json:"issued_at"`  // Token issue time
	Issuer    string    `json:"iss"`        // Token issuer (Cognito URL)
	Audience  string    `json:"aud"`        // Token audience (client ID)
	TokenUse  string    `json:"token_use"`  // Token type (access or id)
}

const claimsKey = "auth_claims"

// GetClaims retrieves the authenticated user's claims from the Gin context.
// Returns nil if no claims are present (unauthenticated request).
func GetClaims(c *gin.Context) *Claims {
	if claims, exists := c.Get(claimsKey); exists {
		if c, ok := claims.(*Claims); ok {
			return c
		}
	}
	return nil
}

// SetClaims stores the authenticated user's claims in the Gin context.
func SetClaims(c *gin.Context, claims *Claims) {
	c.Set(claimsKey, claims)
}

// GetUserID is a convenience function to get the user's Cognito sub (UUID).
// Returns empty string if not authenticated.
func GetUserID(c *gin.Context) string {
	if claims := GetClaims(c); claims != nil {
		return claims.Sub
	}
	return ""
}

// GetEmail is a convenience function to get the user's email.
// Returns empty string if not authenticated.
func GetEmail(c *gin.Context) string {
	if claims := GetClaims(c); claims != nil {
		return claims.Email
	}
	return ""
}

// IsAuthenticated returns true if the request has valid authentication claims.
func IsAuthenticated(c *gin.Context) bool {
	return GetClaims(c) != nil
}

// HasGroup checks if the authenticated user belongs to a specific Cognito group.
func HasGroup(c *gin.Context, group string) bool {
	claims := GetClaims(c)
	if claims == nil {
		return false
	}
	for _, g := range claims.Groups {
		if g == group {
			return true
		}
	}
	return false
}
