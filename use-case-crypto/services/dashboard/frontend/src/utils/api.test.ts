import { describe, it, expect, beforeEach, vi, afterEach } from "vitest";
import {
  authApi,
  predictionsApi,
  metricsApi,
  modelsApi,
  featuresApi,
  symbolsApi,
} from "./api";

// Mock global fetch
const mockFetch = vi.fn();
global.fetch = mockFetch;

describe("API utilities", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
    localStorage.setItem("token", "test-token");
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  const mockJsonResponse = (data: any, status = 200) => {
    mockFetch.mockResolvedValueOnce({
      ok: status >= 200 && status < 300,
      status,
      json: () => Promise.resolve(data),
    });
  };

  describe("authApi", () => {
    it("should call login endpoint with credentials", async () => {
      const mockResponse = {
        access_token: "test-token",
        user: { id: 1, username: "test" },
      };
      mockJsonResponse(mockResponse);

      const result = await authApi.login("testuser", "password123");

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/auth/login",
        expect.objectContaining({
          method: "POST",
          body: JSON.stringify({
            username: "testuser",
            password: "password123",
          }),
        }),
      );
      expect(result).toEqual(mockResponse);
    });

    it("should fetch roles", async () => {
      const mockResponse = ["data_engineer", "data_scientist"];
      mockJsonResponse(mockResponse);

      const result = await authApi.getRoles();

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/auth/roles",
        expect.objectContaining({
          headers: expect.objectContaining({
            Authorization: "Bearer test-token",
          }),
        }),
      );
      expect(result).toEqual(mockResponse);
    });
  });

  describe("predictionsApi", () => {
    it("should get all predictions", async () => {
      mockJsonResponse([]);

      await predictionsApi.getAll();

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/predictions",
        expect.any(Object),
      );
    });

    it("should get predictions by symbol with default limit", async () => {
      mockJsonResponse([]);

      await predictionsApi.getBySymbol("SYMBOL-1");

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/predictions/SYMBOL-1?limit=100",
        expect.any(Object),
      );
    });

    it("should get predictions by symbol with custom limit", async () => {
      mockJsonResponse([]);

      await predictionsApi.getBySymbol("SYMBOL-2", 50);

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/predictions/SYMBOL-2?limit=50",
        expect.any(Object),
      );
    });

    it("should get latest prediction", async () => {
      const mockResponse = { symbol: "SYMBOL-1", signal: 1 };
      mockJsonResponse(mockResponse);

      const result = await predictionsApi.getLatest("SYMBOL-1");

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/predictions/SYMBOL-1/latest",
        expect.any(Object),
      );
      expect(result).toEqual(mockResponse);
    });
  });

  describe("metricsApi", () => {
    it("should get quality metrics without symbol", async () => {
      mockJsonResponse({});

      await metricsApi.getQuality();

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/metrics/quality",
        expect.any(Object),
      );
    });

    it("should get quality metrics with symbol", async () => {
      mockJsonResponse({});

      await metricsApi.getQuality("SYMBOL-1");

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/metrics/quality?symbol=SYMBOL-1",
        expect.any(Object),
      );
    });

    it("should get drift metrics for symbol", async () => {
      mockJsonResponse({ drift: 0.05 });

      await metricsApi.getDrift("SYMBOL-1");

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/metrics/drift/SYMBOL-1",
        expect.any(Object),
      );
    });

    it("should get all drift metrics", async () => {
      mockJsonResponse([]);

      await metricsApi.getAllDrift();

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/metrics/drift",
        expect.any(Object),
      );
    });

    it("should get model metrics", async () => {
      mockJsonResponse({});

      await metricsApi.getModels();

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/metrics/models",
        expect.any(Object),
      );
    });

    it("should get system metrics", async () => {
      mockJsonResponse({});

      await metricsApi.getSystem();

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/metrics/system",
        expect.any(Object),
      );
    });

    it("should get summary metrics", async () => {
      mockJsonResponse({});

      await metricsApi.getSummary();

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/metrics/summary",
        expect.any(Object),
      );
    });
  });

  describe("modelsApi", () => {
    it("should get all models without stage filter", async () => {
      mockJsonResponse([]);

      await modelsApi.getAll();

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/models",
        expect.any(Object),
      );
    });

    it("should get models filtered by stage", async () => {
      mockJsonResponse([]);

      await modelsApi.getAll("Production");

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/models?stage=Production",
        expect.any(Object),
      );
    });

    it("should get model details", async () => {
      mockJsonResponse({ name: "test-model" });

      await modelsApi.getDetails("test-model");

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/models/test-model",
        expect.any(Object),
      );
    });

    it("should get model versions", async () => {
      mockJsonResponse([]);

      await modelsApi.getVersions("test-model");

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/models/test-model/versions",
        expect.any(Object),
      );
    });

    it("should deploy model with default stage", async () => {
      mockJsonResponse({ status: "deployed" });

      await modelsApi.deploy("test-model", "v1.0");

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/models/deploy",
        expect.objectContaining({
          method: "POST",
          body: JSON.stringify({
            model_name: "test-model",
            version: "v1.0",
            stage: "Production",
          }),
        }),
      );
    });

    it("should deploy model with custom stage", async () => {
      mockJsonResponse({ status: "deployed" });

      await modelsApi.deploy("test-model", "v1.0", "Staging");

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/models/deploy",
        expect.objectContaining({
          method: "POST",
          body: JSON.stringify({
            model_name: "test-model",
            version: "v1.0",
            stage: "Staging",
          }),
        }),
      );
    });
  });

  describe("featuresApi", () => {
    it("should get all features without entity filter", async () => {
      mockJsonResponse([]);

      await featuresApi.getAll();

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/features",
        expect.any(Object),
      );
    });

    it("should get features filtered by entity", async () => {
      mockJsonResponse([]);

      await featuresApi.getAll("data");

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/features?entity=data",
        expect.any(Object),
      );
    });

    it("should get features by symbol with default hours", async () => {
      mockJsonResponse([]);

      await featuresApi.getBySymbol("SYMBOL-1");

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/features/SYMBOL-1?hours=24",
        expect.any(Object),
      );
    });

    it("should get features by symbol with custom hours", async () => {
      mockJsonResponse([]);

      await featuresApi.getBySymbol("SYMBOL-2", 48);

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/features/SYMBOL-2?hours=48",
        expect.any(Object),
      );
    });

    it("should get latest features", async () => {
      mockJsonResponse({});

      await featuresApi.getLatest("SYMBOL-1");

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/features/SYMBOL-1/latest",
        expect.any(Object),
      );
    });

    it("should get feature statistics", async () => {
      mockJsonResponse({});

      await featuresApi.getStatistics("SYMBOL-1");

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/features/statistics/SYMBOL-1",
        expect.any(Object),
      );
    });
  });

  describe("symbolsApi", () => {
    it("should get all symbols", async () => {
      const mockResponse = ["SYMBOL-1", "SYMBOL-2"];
      mockJsonResponse(mockResponse);

      const result = await symbolsApi.getAll();

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/v1/symbols",
        expect.any(Object),
      );
      expect(result).toEqual(mockResponse);
    });
  });

  describe("error handling", () => {
    it("should throw on non-OK response", async () => {
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 500,
        json: () => Promise.resolve({ detail: "Server error" }),
      });

      await expect(predictionsApi.getAll()).rejects.toThrow("API error: 500");
    });

    it("should handle 401 and redirect to login", async () => {
      const originalLocation = window.location;

      // Mock window.location
      Object.defineProperty(window, "location", {
        value: { href: "" },
        writable: true,
      });

      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 401,
        json: () => Promise.resolve({ detail: "Unauthorized" }),
      });

      await expect(predictionsApi.getAll()).rejects.toThrow("Unauthorized");
      expect(localStorage.getItem("token")).toBeNull();
      expect(localStorage.getItem("user")).toBeNull();
      expect(window.location.href).toBe("/login");

      // Restore
      Object.defineProperty(window, "location", {
        value: originalLocation,
        writable: true,
      });
    });
  });
});
