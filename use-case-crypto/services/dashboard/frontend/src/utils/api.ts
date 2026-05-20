import type { Token } from "../types";

const API_BASE_URL = "/api/v1";

async function apiFetch<T>(url: string, init?: RequestInit): Promise<T> {
  const token = localStorage.getItem("token");
  const res = await fetch(`${API_BASE_URL}${url}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...init?.headers,
    },
  });

  if (res.status === 401) {
    localStorage.removeItem("token");
    localStorage.removeItem("user");
    window.location.href = "/login";
    throw new Error("Unauthorized");
  }

  if (!res.ok) {
    throw new Error(`API error: ${res.status}`);
  }

  return res.json();
}

// Auth API
export const authApi = {
  login: async (username: string, password: string): Promise<Token> => {
    return apiFetch<Token>("/auth/login", {
      method: "POST",
      body: JSON.stringify({ username, password }),
    });
  },
  getRoles: async () => {
    return apiFetch<string[]>("/auth/roles");
  },
};

// Predictions API
export const predictionsApi = {
  getAll: async () => {
    return apiFetch<any>("/predictions");
  },
  getBySymbol: async (symbol: string, limit = 100) => {
    return apiFetch<any>(`/predictions/${symbol}?limit=${limit}`);
  },
  getLatest: async (symbol: string) => {
    return apiFetch<any>(`/predictions/${symbol}/latest`);
  },
};

// Metrics API
export const metricsApi = {
  getQuality: async (symbol?: string) => {
    const url = symbol
      ? `/metrics/quality?symbol=${symbol}`
      : "/metrics/quality";
    return apiFetch<any>(url);
  },
  getDrift: async (symbol: string) => {
    return apiFetch<any>(`/metrics/drift/${symbol}`);
  },
  getAllDrift: async () => {
    return apiFetch<any>("/metrics/drift");
  },
  getModels: async () => {
    return apiFetch<any>("/metrics/models");
  },
  getSystem: async () => {
    return apiFetch<any>("/metrics/system");
  },
  getSummary: async () => {
    return apiFetch<any>("/metrics/summary");
  },
};

// Models API
export const modelsApi = {
  getAll: async (stage?: string) => {
    const url = stage ? `/models?stage=${stage}` : "/models";
    return apiFetch<any>(url);
  },
  getDetails: async (modelName: string) => {
    return apiFetch<any>(`/models/${modelName}`);
  },
  getVersions: async (modelName: string) => {
    return apiFetch<any>(`/models/${modelName}/versions`);
  },
  deploy: async (modelName: string, version: string, stage = "Production") => {
    return apiFetch<any>("/models/deploy", {
      method: "POST",
      body: JSON.stringify({
        model_name: modelName,
        version,
        stage,
      }),
    });
  },
};

// Features API
export const featuresApi = {
  getAll: async (entity?: string) => {
    const url = entity ? `/features?entity=${entity}` : "/features";
    return apiFetch<any>(url);
  },
  getBySymbol: async (symbol: string, hours = 24) => {
    return apiFetch<any>(`/features/${symbol}?hours=${hours}`);
  },
  getLatest: async (symbol: string) => {
    return apiFetch<any>(`/features/${symbol}/latest`);
  },
  getStatistics: async (symbol: string) => {
    return apiFetch<any>(`/features/statistics/${symbol}`);
  },
};

// Symbols API
export const symbolsApi = {
  getAll: async () => {
    return apiFetch<any>("/symbols");
  },
};
