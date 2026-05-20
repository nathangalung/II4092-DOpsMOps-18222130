// Config loader for dashboard backend.
package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"time"

	"gopkg.in/yaml.v3"
)

// Config holds all configuration.
type Config struct {
	Server     ServerConfig     `yaml:"server"`
	Auth       AuthConfig       `yaml:"auth"`
	Redis      RedisConfig      `yaml:"redis"`
	ClickHouse ClickHouseConfig `yaml:"clickhouse"`
	MLBridge   MLBridgeConfig   `yaml:"ml_bridge"`
	MLflow     MLflowConfig     `yaml:"mlflow"`
}

// ServerConfig for HTTP server.
type ServerConfig struct {
	Port         int           `yaml:"port"`
	ReadTimeout  time.Duration `yaml:"read_timeout"`
	WriteTimeout time.Duration `yaml:"write_timeout"`
}

// AuthConfig for JWT/RBAC.
type AuthConfig struct {
	JWTSecret   string        `yaml:"jwt_secret"`
	TokenExpiry time.Duration `yaml:"token_expiry"`
	Users       []UserConfig  `yaml:"users"`
}

// UserConfig defines a user.
type UserConfig struct {
	Username string `yaml:"username"`
	Password string `yaml:"password"`
	Role     string `yaml:"role"`
}

// RedisConfig for Redis/Valkey connection.
type RedisConfig struct {
	Host string `yaml:"host"`
	Port int    `yaml:"port"`
}

// ClickHouseConfig for ClickHouse.
type ClickHouseConfig struct {
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	Database string `yaml:"database"`
}

// MLBridgeConfig for ML bridge service.
type MLBridgeConfig struct {
	URL string `yaml:"url"`
}

// MLflowConfig for MLflow connection.
type MLflowConfig struct {
	URL string `yaml:"url"`
}

// ErrMissingSecret is returned when a required secret env var is empty.
var ErrMissingSecret = errors.New("required secret is missing")

// defaultUsers defines usernames and roles for the demo dashboard.
// Passwords are injected from USER_<NAME>_PASS env vars (sourced from Vault
// via the pipeline-secrets ExternalSecret); an unset var fails Load().
var defaultUsers = []struct {
	Username, Role, EnvVar string
}{
	{"dataeng", "data_engineer", "USER_DATAENG_PASS"},
	{"datasci", "data_scientist", "USER_DATASCI_PASS"},
	{"mleng", "ml_engineer", "USER_MLENG_PASS"},
	{"bususer", "business_user", "USER_BUSUSER_PASS"},
}

// Load config from file or env.
func Load() (*Config, error) {
	users := make([]UserConfig, 0, len(defaultUsers))
	for _, u := range defaultUsers {
		password := os.Getenv(u.EnvVar)
		if password == "" {
			return nil, fmt.Errorf("%w: %s", ErrMissingSecret, u.EnvVar)
		}
		users = append(users, UserConfig{Username: u.Username, Password: password, Role: u.Role})
	}

	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		return nil, fmt.Errorf("%w: JWT_SECRET", ErrMissingSecret)
	}

	cfg := &Config{
		Server: ServerConfig{
			Port:         getEnvInt("SERVER_PORT", 8080),
			ReadTimeout:  10 * time.Second,
			WriteTimeout: 10 * time.Second,
		},
		Auth: AuthConfig{
			JWTSecret:   jwtSecret,
			TokenExpiry: 24 * time.Hour,
			Users:       users,
		},
		Redis: RedisConfig{
			Host: getEnv("VALKEY_HOST", getEnv("REDIS_HOST", "valkey.storage.svc.cluster.local")),
			Port: getEnvInt("VALKEY_PORT", getEnvInt("REDIS_PORT", 6379)),
		},
		ClickHouse: ClickHouseConfig{
			Host:     getEnv("CLICKHOUSE_HOST", "clickhouse-platform.storage.svc.cluster.local"),
			Port:     getEnvInt("CLICKHOUSE_PORT", 8123),
			Database: getEnv("CLICKHOUSE_DB", "mlops"),
		},
		MLBridge: MLBridgeConfig{
			URL: getEnv("ML_BRIDGE_URL", "http://ml-bridge:8000"),
		},
		MLflow: MLflowConfig{
			URL: getEnv("MLFLOW_TRACKING_URI", "http://mlflow.model-lifecycle.svc.cluster.local:5000"),
		},
	}

	if path := os.Getenv("CONFIG_PATH"); path != "" {
		if data, err := os.ReadFile(path); err == nil {
			_ = yaml.Unmarshal(data, cfg)
		}
	}

	return cfg, nil
}

func getEnv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func getEnvInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if i, err := strconv.Atoi(v); err == nil {
			return i
		}
	}
	return def
}
