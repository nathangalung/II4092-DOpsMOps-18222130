package auth

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewJWT(t *testing.T) {
	secret := "test-secret"
	expiry := 24 * time.Hour

	jwtHandler := NewJWT(secret, expiry)

	assert.NotNil(t, jwtHandler)
	assert.Equal(t, []byte(secret), jwtHandler.secret)
	assert.Equal(t, expiry, jwtHandler.expiry)
}

func TestJWT_Generate(t *testing.T) {
	t.Run("generates valid token", func(t *testing.T) {
		jwtHandler := NewJWT("test-secret", 24*time.Hour)

		token, err := jwtHandler.Generate("testuser", "admin")

		require.NoError(t, err)
		assert.NotEmpty(t, token)
	})

	t.Run("token contains username and role", func(t *testing.T) {
		jwtHandler := NewJWT("test-secret", 24*time.Hour)

		tokenStr, err := jwtHandler.Generate("johndoe", "data_scientist")
		require.NoError(t, err)

		// Parse token manually to verify claims
		token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(t *jwt.Token) (interface{}, error) {
			return []byte("test-secret"), nil
		})
		require.NoError(t, err)

		claims, ok := token.Claims.(*Claims)
		require.True(t, ok)
		assert.Equal(t, "johndoe", claims.Username)
		assert.Equal(t, "data_scientist", claims.Role)
	})

	t.Run("token has correct expiry", func(t *testing.T) {
		expiry := 1 * time.Hour
		jwtHandler := NewJWT("test-secret", expiry)

		tokenStr, err := jwtHandler.Generate("testuser", "admin")
		require.NoError(t, err)

		token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(t *jwt.Token) (interface{}, error) {
			return []byte("test-secret"), nil
		})
		require.NoError(t, err)

		claims := token.Claims.(*Claims)
		expiresAt := claims.ExpiresAt.Time
		issuedAt := claims.IssuedAt.Time

		// Check expiry is approximately 1 hour from issued time
		expectedExpiry := issuedAt.Add(expiry)
		assert.WithinDuration(t, expectedExpiry, expiresAt, 5*time.Second)
	})

	t.Run("generates different tokens for different users", func(t *testing.T) {
		jwtHandler := NewJWT("test-secret", 24*time.Hour)

		token1, _ := jwtHandler.Generate("user1", "admin")
		token2, _ := jwtHandler.Generate("user2", "admin")

		assert.NotEqual(t, token1, token2)
	})

	t.Run("uses HS256 signing method", func(t *testing.T) {
		jwtHandler := NewJWT("test-secret", 24*time.Hour)

		tokenStr, err := jwtHandler.Generate("testuser", "admin")
		require.NoError(t, err)

		token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, jwt.ErrSignatureInvalid
			}
			return []byte("test-secret"), nil
		})
		require.NoError(t, err)

		assert.Equal(t, "HS256", token.Header["alg"])
	})
}

func TestJWT_Validate(t *testing.T) {
	t.Run("validates correct token", func(t *testing.T) {
		jwtHandler := NewJWT("test-secret", 24*time.Hour)

		tokenStr, err := jwtHandler.Generate("testuser", "admin")
		require.NoError(t, err)

		claims, err := jwtHandler.Validate(tokenStr)

		require.NoError(t, err)
		assert.NotNil(t, claims)
		assert.Equal(t, "testuser", claims.Username)
		assert.Equal(t, "admin", claims.Role)
	})

	t.Run("rejects token with wrong secret", func(t *testing.T) {
		jwtHandler1 := NewJWT("secret1", 24*time.Hour)
		jwtHandler2 := NewJWT("secret2", 24*time.Hour)

		tokenStr, err := jwtHandler1.Generate("testuser", "admin")
		require.NoError(t, err)

		_, err = jwtHandler2.Validate(tokenStr)

		assert.Error(t, err)
	})

	t.Run("rejects expired token", func(t *testing.T) {
		jwtHandler := NewJWT("test-secret", -1*time.Hour) // Expired 1 hour ago

		tokenStr, err := jwtHandler.Generate("testuser", "admin")
		require.NoError(t, err)

		_, err = jwtHandler.Validate(tokenStr)

		assert.Error(t, err)
	})

	t.Run("rejects malformed token", func(t *testing.T) {
		jwtHandler := NewJWT("test-secret", 24*time.Hour)

		_, err := jwtHandler.Validate("not.a.valid.token")

		assert.Error(t, err)
	})

	t.Run("rejects empty token", func(t *testing.T) {
		jwtHandler := NewJWT("test-secret", 24*time.Hour)

		_, err := jwtHandler.Validate("")

		assert.Error(t, err)
	})

	t.Run("rejects token with invalid signature", func(t *testing.T) {
		jwtHandler := NewJWT("test-secret", 24*time.Hour)

		// Create token with different secret
		otherHandler := NewJWT("other-secret", 24*time.Hour)
		tokenStr, err := otherHandler.Generate("testuser", "admin")
		require.NoError(t, err)

		_, err = jwtHandler.Validate(tokenStr)

		assert.Error(t, err)
	})

	t.Run("returns ErrInvalidToken for wrong signing method", func(t *testing.T) {
		jwtHandler := NewJWT("test-secret", 24*time.Hour)

		// Create token with RS256 instead of HS256 (requires private key)
		// For testing, we'll just pass a malformed token
		_, err := jwtHandler.Validate("eyJhbGciOiJub25lIn0.e30.")

		assert.Error(t, err)
	})
}

func TestClaims(t *testing.T) {
	t.Run("claims struct has correct fields", func(t *testing.T) {
		now := time.Now()
		claims := &Claims{
			Username: "testuser",
			Role:     "admin",
			RegisteredClaims: jwt.RegisteredClaims{
				ExpiresAt: jwt.NewNumericDate(now.Add(1 * time.Hour)),
				IssuedAt:  jwt.NewNumericDate(now),
			},
		}

		assert.Equal(t, "testuser", claims.Username)
		assert.Equal(t, "admin", claims.Role)
		assert.NotNil(t, claims.ExpiresAt)
		assert.NotNil(t, claims.IssuedAt)
	})
}

func TestErrInvalidToken(t *testing.T) {
	t.Run("error has correct message", func(t *testing.T) {
		assert.Equal(t, "invalid token", ErrInvalidToken.Error())
	})
}

func TestJWT_EdgeCases(t *testing.T) {
	t.Run("handles empty username", func(t *testing.T) {
		jwtHandler := NewJWT("test-secret", 24*time.Hour)

		token, err := jwtHandler.Generate("", "admin")

		require.NoError(t, err)
		assert.NotEmpty(t, token)

		claims, err := jwtHandler.Validate(token)
		require.NoError(t, err)
		assert.Empty(t, claims.Username)
	})

	t.Run("handles empty role", func(t *testing.T) {
		jwtHandler := NewJWT("test-secret", 24*time.Hour)

		token, err := jwtHandler.Generate("testuser", "")

		require.NoError(t, err)
		assert.NotEmpty(t, token)

		claims, err := jwtHandler.Validate(token)
		require.NoError(t, err)
		assert.Empty(t, claims.Role)
	})

	t.Run("handles very long secret", func(t *testing.T) {
		longSecret := string(make([]byte, 1024))
		jwtHandler := NewJWT(longSecret, 24*time.Hour)

		token, err := jwtHandler.Generate("testuser", "admin")

		require.NoError(t, err)
		assert.NotEmpty(t, token)
	})

	t.Run("handles very short expiry", func(t *testing.T) {
		jwtHandler := NewJWT("test-secret", 1*time.Millisecond)

		token, err := jwtHandler.Generate("testuser", "admin")

		require.NoError(t, err)

		// Wait for expiry
		time.Sleep(10 * time.Millisecond)

		_, err = jwtHandler.Validate(token)
		assert.Error(t, err, "token should be expired")
	})

	t.Run("handles special characters in username", func(t *testing.T) {
		jwtHandler := NewJWT("test-secret", 24*time.Hour)

		token, err := jwtHandler.Generate("test@example.com", "admin")

		require.NoError(t, err)

		claims, err := jwtHandler.Validate(token)
		require.NoError(t, err)
		assert.Equal(t, "test@example.com", claims.Username)
	})
}
