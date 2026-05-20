package services

import (
	"context"
	"os"
	"testing"

	"github.com/mlops-platform/dashboard/internal/config"
	"github.com/stretchr/testify/assert"
)

func TestNewFeatureService(t *testing.T) {
	t.Run("creates service with config", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "mlops",
			},
		}

		svc := NewFeatureService(cfg)

		assert.NotNil(t, svc)
	})
}

func TestFeatureService_List(t *testing.T) {
	t.Run("returns empty list when no db and no env var", func(t *testing.T) {
		svc := &FeatureService{db: nil}

		features, err := svc.List(context.Background(), "")

		assert.NoError(t, err)
		assert.Empty(t, features)
	})

	t.Run("returns features from FEATURE_DEFINITIONS env var", func(t *testing.T) {
		os.Setenv("FEATURE_DEFINITIONS", "value_a:Primary value:float64,value_b:Secondary value:float64,indicator_x:An indicator:float64")
		defer os.Unsetenv("FEATURE_DEFINITIONS")

		svc := &FeatureService{db: nil}

		features, err := svc.List(context.Background(), "")

		assert.NoError(t, err)
		assert.Len(t, features, 3)
		assert.Equal(t, "value_a", features[0].Name)
		assert.Equal(t, "Primary value", features[0].Description)
		assert.Equal(t, "float64", features[0].Type)
	})

	t.Run("symbol parameter is accepted", func(t *testing.T) {
		os.Setenv("FEATURE_DEFINITIONS", "value_a:A value:float64")
		defer os.Unsetenv("FEATURE_DEFINITIONS")

		svc := &FeatureService{db: nil}

		features, err := svc.List(context.Background(), "SYMBOL-1")

		assert.NoError(t, err)
		assert.NotEmpty(t, features)
	})
}

func TestFeatureService_Get(t *testing.T) {
	t.Run("returns empty when db is nil", func(t *testing.T) {
		svc := &FeatureService{db: nil}

		features, err := svc.Get(context.Background(), "value_1", "SYMBOL-1")

		assert.NoError(t, err)
		assert.Empty(t, features)
	})

	t.Run("validates feature name parameter", func(t *testing.T) {
		svc := &FeatureService{db: nil}

		featureNames := []string{"value_a", "value_b", "indicator_x", ""}

		for _, name := range featureNames {
			features, err := svc.Get(context.Background(), name, "SYMBOL-1")

			assert.NoError(t, err)
			assert.Empty(t, features)
		}
	})
}

func TestFeatureDefinition_Structure(t *testing.T) {
	t.Run("feature definition has correct fields", func(t *testing.T) {
		fd := FeatureDefinition{
			Name:        "value_a",
			Description: "Primary value",
			Type:        "float64",
			Tags:        []string{"raw", "value"},
		}

		assert.Equal(t, "value_a", fd.Name)
		assert.Equal(t, "Primary value", fd.Description)
		assert.Equal(t, "float64", fd.Type)
		assert.Contains(t, fd.Tags, "raw")
	})
}

func TestFeature_Structure(t *testing.T) {
	t.Run("feature has correct fields", func(t *testing.T) {
		f := Feature{
			Symbol: "SYMBOL-1",
			Name:   "value_a",
			Value:  500.0,
			Metadata: map[string]interface{}{
				"source": "pipeline",
			},
		}

		assert.Equal(t, "SYMBOL-1", f.Symbol)
		assert.Equal(t, "value_a", f.Name)
		assert.Equal(t, 500.0, f.Value)
		assert.NotNil(t, f.Metadata)
		assert.Equal(t, "pipeline", f.Metadata["source"])
	})
}

func TestFeatureService_ListCategories(t *testing.T) {
	t.Run("features from env have configured tag", func(t *testing.T) {
		os.Setenv("FEATURE_DEFINITIONS", "value_a:Primary:float64,value_b:Secondary:float64")
		defer os.Unsetenv("FEATURE_DEFINITIONS")

		svc := &FeatureService{db: nil}

		features, err := svc.List(context.Background(), "")
		assert.NoError(t, err)

		for _, f := range features {
			assert.Contains(t, f.Tags, "configured")
		}
	})
}
