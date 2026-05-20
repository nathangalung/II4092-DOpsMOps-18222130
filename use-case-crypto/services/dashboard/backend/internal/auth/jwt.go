// JWT token handling.
package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// ErrInvalidToken returned for invalid tokens.
var ErrInvalidToken = errors.New("invalid token")

// Claims holds JWT claims.
type Claims struct {
	Username string `json:"username"`
	Role     string `json:"role"`
	jwt.RegisteredClaims
}

// JWT handles token operations.
type JWT struct {
	secret []byte
	expiry time.Duration
}

// NewJWT creates JWT handler.
func NewJWT(secret string, expiry time.Duration) *JWT {
	return &JWT{
		secret: []byte(secret),
		expiry: expiry,
	}
}

// Generate creates a new token.
func (j *JWT) Generate(username, role string) (string, error) {
	claims := &Claims{
		Username: username,
		Role:     role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(j.expiry)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(j.secret)
}

// Validate parses and validates token.
func (j *JWT) Validate(tokenStr string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, ErrInvalidToken
		}
		return j.secret, nil
	})

	if err != nil {
		return nil, err
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, ErrInvalidToken
	}

	return claims, nil
}
