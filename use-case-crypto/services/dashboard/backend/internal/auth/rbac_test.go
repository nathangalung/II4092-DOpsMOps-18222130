package auth

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNewRBAC(t *testing.T) {
	rbac := NewRBAC()

	assert.NotNil(t, rbac)
	assert.NotNil(t, rbac.permissions)
	assert.Len(t, rbac.permissions, 4) // 4 default roles
}

func TestRBAC_HasPermission(t *testing.T) {
	rbac := NewRBAC()

	t.Run("data_engineer has correct permissions", func(t *testing.T) {
		testCases := []struct {
			permission string
			expected   bool
		}{
			{"ingestion:read", true},
			{"ingestion:write", true},
			{"processing:read", true},
			{"quality:read", true},
			{"dashboard:read", true},
			{"features:read", false},
			{"training:write", false},
		}

		for _, tc := range testCases {
			result := rbac.HasPermission("data_engineer", tc.permission)
			assert.Equal(t, tc.expected, result,
				"data_engineer should %v for %s", tc.expected, tc.permission)
		}
	})

	t.Run("data_scientist has correct permissions", func(t *testing.T) {
		testCases := []struct {
			permission string
			expected   bool
		}{
			{"features:read", true},
			{"features:write", true},
			{"training:read", true},
			{"experiments:read", true},
			{"dashboard:read", true},
			{"ingestion:write", false},
			{"deployment:write", false},
		}

		for _, tc := range testCases {
			result := rbac.HasPermission("data_scientist", tc.permission)
			assert.Equal(t, tc.expected, result,
				"data_scientist should %v for %s", tc.expected, tc.permission)
		}
	})

	t.Run("ml_engineer has correct permissions", func(t *testing.T) {
		testCases := []struct {
			permission string
			expected   bool
		}{
			{"serving:read", true},
			{"serving:write", true},
			{"monitoring:read", true},
			{"deployment:read", true},
			{"dashboard:read", true},
			{"dashboard:write", true},
			{"ingestion:write", false},
			{"training:read", false},
		}

		for _, tc := range testCases {
			result := rbac.HasPermission("ml_engineer", tc.permission)
			assert.Equal(t, tc.expected, result,
				"ml_engineer should %v for %s", tc.expected, tc.permission)
		}
	})

	t.Run("business_user has correct permissions", func(t *testing.T) {
		testCases := []struct {
			permission string
			expected   bool
		}{
			{"dashboard:read", true},
			{"predictions:read", true},
			{"dashboard:write", false},
			{"ingestion:read", false},
			{"features:read", false},
		}

		for _, tc := range testCases {
			result := rbac.HasPermission("business_user", tc.permission)
			assert.Equal(t, tc.expected, result,
				"business_user should %v for %s", tc.expected, tc.permission)
		}
	})

	t.Run("unknown role has no permissions", func(t *testing.T) {
		assert.False(t, rbac.HasPermission("unknown_role", "any:permission"))
		assert.False(t, rbac.HasPermission("", "any:permission"))
	})

	t.Run("wildcard resource matches all resources", func(t *testing.T) {
		// data_engineer has "ingestion:*"
		assert.True(t, rbac.HasPermission("data_engineer", "ingestion:read"))
		assert.True(t, rbac.HasPermission("data_engineer", "ingestion:write"))
		assert.True(t, rbac.HasPermission("data_engineer", "ingestion:delete"))
	})

	t.Run("wildcard action matches all actions", func(t *testing.T) {
		// ml_engineer has "dashboard:*"
		assert.True(t, rbac.HasPermission("ml_engineer", "dashboard:read"))
		assert.True(t, rbac.HasPermission("ml_engineer", "dashboard:write"))
		assert.True(t, rbac.HasPermission("ml_engineer", "dashboard:delete"))
	})
}

func TestSplitPermission(t *testing.T) {
	testCases := []struct {
		permission string
		resource   string
		action     string
	}{
		{"ingestion:read", "ingestion", "read"},
		{"features:write", "features", "write"},
		{"dashboard:*", "dashboard", "*"},
		{"*:read", "*", "read"},
		{"*:*", "*", "*"},
		{"invalid", "invalid", "*"}, // No colon defaults to *
	}

	for _, tc := range testCases {
		resource, action := splitPermission(tc.permission)
		assert.Equal(t, tc.resource, resource,
			"resource mismatch for %s", tc.permission)
		assert.Equal(t, tc.action, action,
			"action mismatch for %s", tc.permission)
	}
}

func TestMatchResource(t *testing.T) {
	testCases := []struct {
		pattern  string
		resource string
		expected bool
	}{
		{"*", "anything", true},
		{"*", "", true},
		{"ingestion", "ingestion", true},
		{"ingestion", "processing", false},
		{"dashboard", "dashboard", true},
		{"", "", true},
	}

	for _, tc := range testCases {
		result := matchResource(tc.pattern, tc.resource)
		assert.Equal(t, tc.expected, result,
			"pattern %s should %v match resource %s", tc.pattern, tc.expected, tc.resource)
	}
}

func TestMatchAction(t *testing.T) {
	testCases := []struct {
		pattern  string
		action   string
		expected bool
	}{
		{"*", "read", true},
		{"*", "write", true},
		{"*", "", true},
		{"read", "read", true},
		{"read", "write", false},
		{"write", "write", true},
		{"delete", "read", false},
	}

	for _, tc := range testCases {
		result := matchAction(tc.pattern, tc.action)
		assert.Equal(t, tc.expected, result,
			"pattern %s should %v match action %s", tc.pattern, tc.expected, tc.action)
	}
}

func TestRBAC_ComplexPermissions(t *testing.T) {
	rbac := NewRBAC()

	t.Run("multiple wildcard patterns work", func(t *testing.T) {
		// data_scientist has "features:*", "training:*", "experiments:*"
		assert.True(t, rbac.HasPermission("data_scientist", "features:read"))
		assert.True(t, rbac.HasPermission("data_scientist", "features:create"))
		assert.True(t, rbac.HasPermission("data_scientist", "training:execute"))
		assert.True(t, rbac.HasPermission("data_scientist", "experiments:analyze"))
	})

	t.Run("specific permission without wildcard", func(t *testing.T) {
		// business_user has "dashboard:read" (not wildcard)
		assert.True(t, rbac.HasPermission("business_user", "dashboard:read"))
		assert.False(t, rbac.HasPermission("business_user", "dashboard:write"))
	})

	t.Run("case sensitive permission check", func(t *testing.T) {
		// Permissions are case-sensitive
		assert.False(t, rbac.HasPermission("data_engineer", "INGESTION:READ"))
		assert.False(t, rbac.HasPermission("DATA_ENGINEER", "ingestion:read"))
	})
}

func TestRBAC_EdgeCases(t *testing.T) {
	rbac := NewRBAC()

	t.Run("empty permission string", func(t *testing.T) {
		result := rbac.HasPermission("data_engineer", "")
		// Empty permission becomes ":*" after split
		assert.False(t, result)
	})

	t.Run("permission with multiple colons", func(t *testing.T) {
		resource, action := splitPermission("resource:action:extra")
		assert.Equal(t, "resource", resource)
		assert.Equal(t, "action:extra", action)
	})

	t.Run("permission with only colon", func(t *testing.T) {
		resource, action := splitPermission(":")
		assert.Equal(t, "", resource)
		assert.Equal(t, "", action)
	})

	t.Run("nil permissions map for unknown role", func(t *testing.T) {
		result := rbac.HasPermission("nonexistent_role", "any:permission")
		assert.False(t, result)
	})
}

func TestRBAC_AllRolesDefinitions(t *testing.T) {
	rbac := NewRBAC()

	t.Run("all roles are defined", func(t *testing.T) {
		expectedRoles := []string{
			"data_engineer",
			"data_scientist",
			"ml_engineer",
			"business_user",
		}

		for _, role := range expectedRoles {
			perms, exists := rbac.permissions[role]
			assert.True(t, exists, "role %s should exist", role)
			assert.NotEmpty(t, perms, "role %s should have permissions", role)
		}
	})

	t.Run("each role has at least one permission", func(t *testing.T) {
		for role, perms := range rbac.permissions {
			assert.NotEmpty(t, perms, "role %s should have at least one permission", role)
		}
	})

	t.Run("all roles have dashboard:read", func(t *testing.T) {
		roles := []string{"data_engineer", "data_scientist", "ml_engineer", "business_user"}

		for _, role := range roles {
			assert.True(t, rbac.HasPermission(role, "dashboard:read"),
				"role %s should have dashboard:read permission", role)
		}
	})
}
