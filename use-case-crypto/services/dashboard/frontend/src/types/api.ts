// API response types

export interface ApiResponse<T> {
  success: boolean;
  data: T;
  error?: string;
}

export interface PaginatedResponse<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
}

export interface HealthStatus {
  status: "healthy" | "degraded" | "unhealthy";
  services: Record<string, boolean>;
}
