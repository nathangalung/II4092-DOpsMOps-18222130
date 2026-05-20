import { describe, it, expect, beforeEach, vi } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";
import { AuthProvider, useAuth } from "./AuthContext";
import { authApi } from "../utils/api";
import type { Token, User } from "../types";

vi.mock("../utils/api", () => ({
  authApi: {
    login: vi.fn(),
    getRoles: vi.fn(),
  },
}));

describe("AuthContext", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
  });

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <AuthProvider>{children}</AuthProvider>
  );

  const mockUser: User = {
    id: "1",
    username: "testuser",
    email: "test@example.com",
    role: "data_engineer",
    is_active: true,
    created_at: "2024-01-01T00:00:00Z",
    permissions: ["predictions:read", "models:*"],
  };

  const mockToken: Token = {
    access_token: "test-token-123",
    token_type: "bearer",
    expires_in: 3600,
    user: mockUser,
  };

  it("should throw error when useAuth is used outside AuthProvider", () => {
    expect(() => {
      renderHook(() => useAuth());
    }).toThrow("useAuth must be used within an AuthProvider");
  });

  it("should initialize with null user and token", () => {
    const { result } = renderHook(() => useAuth(), { wrapper });

    expect(result.current.user).toBeNull();
    expect(result.current.token).toBeNull();
    expect(result.current.isAuthenticated).toBe(false);
  });

  it("should load user from localStorage on mount", () => {
    localStorage.setItem("token", "stored-token");
    localStorage.setItem("user", JSON.stringify(mockUser));

    const { result } = renderHook(() => useAuth(), { wrapper });

    waitFor(() => {
      expect(result.current.token).toBe("stored-token");
      expect(result.current.user).toEqual(mockUser);
      expect(result.current.isAuthenticated).toBe(true);
    });
  });

  it("should handle login successfully", async () => {
    vi.mocked(authApi.login).mockResolvedValue(mockToken);

    const { result } = renderHook(() => useAuth(), { wrapper });

    await act(async () => {
      await result.current.login("testuser", "password123");
    });

    expect(authApi.login).toHaveBeenCalledWith("testuser", "password123");
    expect(result.current.token).toBe(mockToken.access_token);
    expect(result.current.user).toEqual(mockUser);
    expect(result.current.isAuthenticated).toBe(true);
    expect(localStorage.getItem("token")).toBe(mockToken.access_token);
    expect(localStorage.getItem("user")).toBe(JSON.stringify(mockUser));
  });

  it("should handle logout", async () => {
    localStorage.setItem("token", "test-token");
    localStorage.setItem("user", JSON.stringify(mockUser));

    const { result } = renderHook(() => useAuth(), { wrapper });

    act(() => {
      result.current.logout();
    });

    expect(result.current.token).toBeNull();
    expect(result.current.user).toBeNull();
    expect(result.current.isAuthenticated).toBe(false);
    expect(localStorage.getItem("token")).toBeNull();
    expect(localStorage.getItem("user")).toBeNull();
  });

  describe("hasRole", () => {
    it("should return true when user has the role", () => {
      localStorage.setItem("token", "test-token");
      localStorage.setItem("user", JSON.stringify(mockUser));

      const { result } = renderHook(() => useAuth(), { wrapper });

      waitFor(() => {
        expect(result.current.hasRole(["data_engineer"])).toBe(true);
        expect(
          result.current.hasRole(["data_engineer", "data_scientist"]),
        ).toBe(true);
      });
    });

    it("should return false when user does not have the role", () => {
      localStorage.setItem("token", "test-token");
      localStorage.setItem("user", JSON.stringify(mockUser));

      const { result } = renderHook(() => useAuth(), { wrapper });

      waitFor(() => {
        expect(result.current.hasRole(["data_scientist"])).toBe(false);
        expect(result.current.hasRole(["ml_engineer", "business_user"])).toBe(
          false,
        );
      });
    });

    it("should return false when user is null", () => {
      const { result } = renderHook(() => useAuth(), { wrapper });

      expect(result.current.hasRole(["data_engineer"])).toBe(false);
    });
  });

  describe("hasPermission", () => {
    beforeEach(() => {
      localStorage.setItem("token", "test-token");
      localStorage.setItem("user", JSON.stringify(mockUser));
    });

    it("should return true for exact permission match", () => {
      const { result } = renderHook(() => useAuth(), { wrapper });

      waitFor(() => {
        expect(result.current.hasPermission("predictions:read")).toBe(true);
      });
    });

    it("should return true for wildcard permission match", () => {
      const { result } = renderHook(() => useAuth(), { wrapper });

      waitFor(() => {
        expect(result.current.hasPermission("models:read")).toBe(true);
        expect(result.current.hasPermission("models:write")).toBe(true);
        expect(result.current.hasPermission("models:delete")).toBe(true);
      });
    });

    it("should return false when permission is not granted", () => {
      const { result } = renderHook(() => useAuth(), { wrapper });

      waitFor(() => {
        expect(result.current.hasPermission("admin:delete")).toBe(false);
        expect(result.current.hasPermission("users:write")).toBe(false);
      });
    });

    it("should return false when user is null", () => {
      localStorage.clear();
      const { result } = renderHook(() => useAuth(), { wrapper });

      expect(result.current.hasPermission("predictions:read")).toBe(false);
    });
  });

  it("should set isLoading to false after initialization", () => {
    const { result } = renderHook(() => useAuth(), { wrapper });

    waitFor(() => {
      expect(result.current.isLoading).toBe(false);
    });
  });

  it("should handle login error", async () => {
    vi.mocked(authApi.login).mockRejectedValue(
      new Error("Invalid credentials"),
    );

    const { result } = renderHook(() => useAuth(), { wrapper });

    await expect(async () => {
      await act(async () => {
        await result.current.login("testuser", "wrongpassword");
      });
    }).rejects.toThrow("Invalid credentials");

    expect(result.current.isAuthenticated).toBe(false);
  });
});
