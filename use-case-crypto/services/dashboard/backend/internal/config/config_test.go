package config

import (
	"errors"
	"os"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// setTestSecrets sets every required secret env var so Load() succeeds.
func setTestSecrets(t *testing.T) {
	t.Helper()
	t.Setenv("JWT_SECRET", "test-secret")
	t.Setenv("USER_DATAENG_PASS", "p-dataeng")
	t.Setenv("USER_DATASCI_PASS", "p-datasci")
	t.Setenv("USER_MLENG_PASS", "p-mleng")
	t.Setenv("USER_BUSUSER_PASS", "p-bususer")
}

func TestLoad(t *testing.T) {
	t.Run("fails when required secret missing", func(t *testing.T) {
		t.Setenv("JWT_SECRET", "")
		t.Setenv("USER_DATAENG_PASS", "")
		t.Setenv("USER_DATASCI_PASS", "")
		t.Setenv("USER_MLENG_PASS", "")
		t.Setenv("USER_BUSUSER_PASS", "")

		_, err := Load()
		require.Error(t, err)
		assert.True(t, errors.Is(err, ErrMissingSecret))
	})

	t.Run("loads with required secrets", func(t *testing.T) {
		setTestSecrets(t)
		cfg, err := Load()

		require.NoError(t, err)
		require.NotNil(t, cfg)

		assert.Equal(t, 8080, cfg.Server.Port)
		assert.Equal(t, 10*time.Second, cfg.Server.ReadTimeout)
		assert.Equal(t, 10*time.Second, cfg.Server.WriteTimeout)

		assert.Equal(t, "test-secret", cfg.Auth.JWTSecret)
		assert.Equal(t, 24*time.Hour, cfg.Auth.TokenExpiry)
		assert.Len(t, cfg.Auth.Users, 4)
	})

	t.Run("loads default users with injected passwords", func(t *testing.T) {
		setTestSecrets(t)
		cfg, err := Load()
		require.NoError(t, err)

		expectedUsers := map[string]string{
			"dataeng": "data_engineer",
			"datasci": "data_scientist",
			"mleng":   "ml_engineer",
			"bususer": "business_user",
		}

		for username, role := range expectedUsers {
			found := false
			for _, user := range cfg.Auth.Users {
				if user.Username == username && user.Role == role {
					found = true
					assert.NotEmpty(t, user.Password, "user %s must have a password", username)
					break
				}
			}
			assert.True(t, found, "should have user %s with role %s", username, role)
		}
	})

	t.Run("loads redis/valkey defaults", func(t *testing.T) {
		setTestSecrets(t)
		cfg, err := Load()

		require.NoError(t, err)
		assert.Equal(t, "valkey.storage.svc.cluster.local", cfg.Redis.Host)
		assert.Equal(t, 6379, cfg.Redis.Port)
	})

	t.Run("loads clickhouse defaults", func(t *testing.T) {
		setTestSecrets(t)
		cfg, err := Load()

		require.NoError(t, err)
		assert.Equal(t, "clickhouse-platform.storage.svc.cluster.local", cfg.ClickHouse.Host)
		assert.Equal(t, 8123, cfg.ClickHouse.Port)
		assert.Equal(t, "mlops", cfg.ClickHouse.Database)
	})

	t.Run("loads ml bridge default", func(t *testing.T) {
		setTestSecrets(t)
		cfg, err := Load()

		require.NoError(t, err)
		assert.Equal(t, "http://ml-bridge:8000", cfg.MLBridge.URL)
	})
}

func TestLoadWithEnvVars(t *testing.T) {
	t.Run("overrides server port from env", func(t *testing.T) {
		setTestSecrets(t)
		t.Setenv("SERVER_PORT", "9090")

		cfg, err := Load()
		require.NoError(t, err)
		assert.Equal(t, 9090, cfg.Server.Port)
	})

	t.Run("uses jwt secret from env", func(t *testing.T) {
		setTestSecrets(t)
		t.Setenv("JWT_SECRET", "custom-secret")

		cfg, err := Load()
		require.NoError(t, err)
		assert.Equal(t, "custom-secret", cfg.Auth.JWTSecret)
	})

	t.Run("overrides valkey host from env (preferred)", func(t *testing.T) {
		setTestSecrets(t)
		t.Setenv("VALKEY_HOST", "custom-valkey")

		cfg, err := Load()
		require.NoError(t, err)
		assert.Equal(t, "custom-valkey", cfg.Redis.Host)
	})

	t.Run("legacy REDIS_HOST still respected", func(t *testing.T) {
		setTestSecrets(t)
		t.Setenv("REDIS_HOST", "custom-redis")

		cfg, err := Load()
		require.NoError(t, err)
		assert.Equal(t, "custom-redis", cfg.Redis.Host)
	})

	t.Run("overrides valkey port from env", func(t *testing.T) {
		setTestSecrets(t)
		t.Setenv("VALKEY_PORT", "7000")

		cfg, err := Load()
		require.NoError(t, err)
		assert.Equal(t, 7000, cfg.Redis.Port)
	})

	t.Run("overrides clickhouse config from env", func(t *testing.T) {
		setTestSecrets(t)
		t.Setenv("CLICKHOUSE_HOST", "custom-ch")
		t.Setenv("CLICKHOUSE_PORT", "9000")
		t.Setenv("CLICKHOUSE_DB", "custom_db")

		cfg, err := Load()
		require.NoError(t, err)
		assert.Equal(t, "custom-ch", cfg.ClickHouse.Host)
		assert.Equal(t, 9000, cfg.ClickHouse.Port)
		assert.Equal(t, "custom_db", cfg.ClickHouse.Database)
	})

	t.Run("overrides ml bridge url from env", func(t *testing.T) {
		setTestSecrets(t)
		t.Setenv("ML_BRIDGE_URL", "http://custom-ml:9000")

		cfg, err := Load()
		require.NoError(t, err)
		assert.Equal(t, "http://custom-ml:9000", cfg.MLBridge.URL)
	})
}

func TestGetEnv(t *testing.T) {
	t.Run("returns env value when set", func(t *testing.T) {
		t.Setenv("TEST_VAR", "value")
		result := getEnv("TEST_VAR", "default")
		assert.Equal(t, "value", result)
	})

	t.Run("returns default when env not set", func(t *testing.T) {
		result := getEnv("NONEXISTENT_VAR", "default")
		assert.Equal(t, "default", result)
	})

	t.Run("returns default when empty string", func(t *testing.T) {
		t.Setenv("TEST_VAR", "")
		result := getEnv("TEST_VAR", "default")
		assert.Equal(t, "default", result)
	})
}

func TestGetEnvInt(t *testing.T) {
	t.Run("returns env value when valid int", func(t *testing.T) {
		t.Setenv("TEST_INT", "42")
		result := getEnvInt("TEST_INT", 10)
		assert.Equal(t, 42, result)
	})

	t.Run("returns default when env not set", func(t *testing.T) {
		result := getEnvInt("NONEXISTENT_INT", 10)
		assert.Equal(t, 10, result)
	})

	t.Run("returns default when invalid int", func(t *testing.T) {
		t.Setenv("TEST_INT", "not_a_number")
		result := getEnvInt("TEST_INT", 10)
		assert.Equal(t, 10, result)
	})

	t.Run("handles negative numbers", func(t *testing.T) {
		t.Setenv("TEST_INT", "-42")
		result := getEnvInt("TEST_INT", 10)
		assert.Equal(t, -42, result)
	})

	t.Run("handles zero", func(t *testing.T) {
		t.Setenv("TEST_INT", "0")
		result := getEnvInt("TEST_INT", 10)
		assert.Equal(t, 0, result)
	})
}

func TestConfigStructs(t *testing.T) {
	t.Run("ServerConfig has correct fields", func(t *testing.T) {
		cfg := ServerConfig{
			Port:         8080,
			ReadTimeout:  5 * time.Second,
			WriteTimeout: 10 * time.Second,
		}
		assert.Equal(t, 8080, cfg.Port)
		assert.Equal(t, 5*time.Second, cfg.ReadTimeout)
		assert.Equal(t, 10*time.Second, cfg.WriteTimeout)
	})

	t.Run("AuthConfig has correct fields", func(t *testing.T) {
		cfg := AuthConfig{
			JWTSecret:   "secret",
			TokenExpiry: 24 * time.Hour,
			Users: []UserConfig{
				{Username: "test", Password: "pass", Role: "admin"},
			},
		}
		assert.Equal(t, "secret", cfg.JWTSecret)
		assert.Equal(t, 24*time.Hour, cfg.TokenExpiry)
		assert.Len(t, cfg.Users, 1)
	})

	t.Run("UserConfig has correct fields", func(t *testing.T) {
		user := UserConfig{
			Username: "testuser",
			Password: "testpass",
			Role:     "admin",
		}
		assert.Equal(t, "testuser", user.Username)
		assert.Equal(t, "testpass", user.Password)
		assert.Equal(t, "admin", user.Role)
	})

	t.Run("RedisConfig has correct fields", func(t *testing.T) {
		cfg := RedisConfig{Host: "localhost", Port: 6379}
		assert.Equal(t, "localhost", cfg.Host)
		assert.Equal(t, 6379, cfg.Port)
	})

	t.Run("ClickHouseConfig has correct fields", func(t *testing.T) {
		cfg := ClickHouseConfig{Host: "localhost", Port: 9000, Database: "test"}
		assert.Equal(t, "localhost", cfg.Host)
		assert.Equal(t, 9000, cfg.Port)
		assert.Equal(t, "test", cfg.Database)
	})

	t.Run("MLBridgeConfig has correct fields", func(t *testing.T) {
		cfg := MLBridgeConfig{URL: "http://ml-bridge:8000"}
		assert.Equal(t, "http://ml-bridge:8000", cfg.URL)
	})
}

func TestLoadFromFile(t *testing.T) {
	t.Run("loads from yaml file when CONFIG_PATH set", func(t *testing.T) {
		setTestSecrets(t)

		tmpFile, err := os.CreateTemp("", "config-*.yaml")
		require.NoError(t, err)
		defer os.Remove(tmpFile.Name())

		yamlContent := `
server:
  port: 7777
auth:
  jwt_secret: "file-secret"
redis:
  host: "file-redis"
  port: 7000
`
		_, err = tmpFile.WriteString(yamlContent)
		require.NoError(t, err)
		tmpFile.Close()

		t.Setenv("CONFIG_PATH", tmpFile.Name())

		cfg, err := Load()
		require.NoError(t, err)
		assert.Equal(t, 7777, cfg.Server.Port)
		assert.Equal(t, "file-secret", cfg.Auth.JWTSecret)
		assert.Equal(t, "file-redis", cfg.Redis.Host)
		assert.Equal(t, 7000, cfg.Redis.Port)
	})

	t.Run("handles missing config file gracefully", func(t *testing.T) {
		setTestSecrets(t)
		t.Setenv("CONFIG_PATH", "/nonexistent/config.yaml")

		cfg, err := Load()
		require.NoError(t, err)
		require.NotNil(t, cfg)
		assert.Equal(t, 8080, cfg.Server.Port)
	})
}

func TestDefaultUsers(t *testing.T) {
	t.Run("all default users have passwords", func(t *testing.T) {
		setTestSecrets(t)
		cfg, err := Load()
		require.NoError(t, err)

		for _, user := range cfg.Auth.Users {
			assert.NotEmpty(t, user.Username)
			assert.NotEmpty(t, user.Password)
			assert.NotEmpty(t, user.Role)
		}
	})

	t.Run("each role has at least one user", func(t *testing.T) {
		setTestSecrets(t)
		cfg, err := Load()
		require.NoError(t, err)

		roles := map[string]bool{}
		for _, user := range cfg.Auth.Users {
			roles[user.Role] = true
		}

		assert.True(t, roles["data_engineer"])
		assert.True(t, roles["data_scientist"])
		assert.True(t, roles["ml_engineer"])
		assert.True(t, roles["business_user"])
	})
}
