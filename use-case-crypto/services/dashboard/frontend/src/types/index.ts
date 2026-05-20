// Crypto-specific API Response Types — overrides generic types with trading fields.

export interface User {
  id: string;
  username: string;
  email?: string;
  full_name?: string;
  role: Role;
  is_active: boolean;
  created_at: string;
  permissions: string[];
}

export type Role =
  | "data_engineer"
  | "data_scientist"
  | "ml_engineer"
  | "business_user";

export interface Token {
  access_token: string;
  token_type: string;
  expires_in: number;
  user: User;
}

export interface Prediction {
  symbol: string;
  predicted_value: number;
  class_index: number;
  class_label: string;
  confidence: number;
  timestamp: string;
  model_version?: string;
  predicted_price?: number;
  signal?: number;
  signal_label?: string;
}

export interface QualityMetrics {
  completeness: number;
  freshness_minutes: number;
  duplicates: number;
  outliers: number;
  last_updated: string;
}

export interface DriftMetrics {
  symbol: string;
  drift_detected: boolean;
  psi: number;
  ks_statistic?: number;
  drifted_features: string[];
  last_checked: string;
}

export interface ModelMetrics {
  model_name: string;
  version: string;
  accuracy?: number;
  mae?: number;
  rmse?: number;
  predictions_count: number;
  last_prediction?: string;
}

export interface SystemMetrics {
  ingestion_rate: number;
  processing_latency_ms: number;
  prediction_latency_ms: number;
  cache_hit_rate: number;
  active_models: number;
}

export interface ModelInfo {
  name: string;
  version: string;
  stage: string;
  description?: string;
  metrics: Record<string, number>;
  created_at: string;
  updated_at?: string;
}

export interface Feature {
  name: string;
  entity: string;
  value_type: string;
  description?: string;
  tags: string[];
}

export interface ApiResponse<T> {
  data: T;
  count?: number;
  timestamp?: string;
}
