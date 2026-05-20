// RBAC permission checking.
package auth

import "strings"

// RBAC handles role-based access control.
type RBAC struct {
	permissions map[string][]string
}

// NewRBAC creates RBAC with default permissions.
func NewRBAC() *RBAC {
	return &RBAC{
		permissions: map[string][]string{
			"data_engineer": {
				"ingestion:*",
				"processing:*",
				"quality:*",
				"dashboard:read",
			},
			"data_scientist": {
				"features:*",
				"training:*",
				"experiments:*",
				"dashboard:read",
			},
			"ml_engineer": {
				"serving:*",
				"monitoring:*",
				"deployment:*",
				"dashboard:*",
			},
			"business_user": {
				"dashboard:read",
				"predictions:read",
			},
		},
	}
}

// HasPermission checks if role has permission.
func (r *RBAC) HasPermission(role, permission string) bool {
	perms, ok := r.permissions[role]
	if !ok {
		return false
	}

	resource, action := splitPermission(permission)

	for _, p := range perms {
		pr, pa := splitPermission(p)
		if matchResource(pr, resource) && matchAction(pa, action) {
			return true
		}
	}

	return false
}

// splitPermission splits "resource:action".
func splitPermission(perm string) (string, string) {
	parts := strings.SplitN(perm, ":", 2)
	if len(parts) != 2 {
		return perm, "*"
	}
	return parts[0], parts[1]
}

// matchResource checks resource match.
func matchResource(pattern, resource string) bool {
	if pattern == "*" {
		return true
	}
	return pattern == resource
}

// matchAction checks action match.
func matchAction(pattern, action string) bool {
	if pattern == "*" {
		return true
	}
	return pattern == action
}
