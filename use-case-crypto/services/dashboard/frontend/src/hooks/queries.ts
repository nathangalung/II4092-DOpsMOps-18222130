import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  predictionsApi,
  metricsApi,
  modelsApi,
  featuresApi,
  symbolsApi,
} from "../utils/api";

// ---- Predictions ----

export const usePredictions = () =>
  useQuery({
    queryKey: ["predictions"],
    queryFn: predictionsApi.getAll,
  });

export const usePredictionsBySymbol = (symbol: string, limit = 100) =>
  useQuery({
    queryKey: ["predictions", symbol, limit],
    queryFn: () => predictionsApi.getBySymbol(symbol, limit),
    enabled: !!symbol,
  });

export const useLatestPrediction = (symbol: string) =>
  useQuery({
    queryKey: ["predictions", symbol, "latest"],
    queryFn: () => predictionsApi.getLatest(symbol),
    enabled: !!symbol,
  });

// ---- Metrics ----

export const useSystemMetrics = () =>
  useQuery({
    queryKey: ["metrics", "system"],
    queryFn: metricsApi.getSystem,
    refetchInterval: 30_000,
  });

export const useQualityMetrics = (symbol?: string) =>
  useQuery({
    queryKey: ["metrics", "quality", symbol],
    queryFn: () => metricsApi.getQuality(symbol),
  });

export const useDriftMetrics = (symbol: string) =>
  useQuery({
    queryKey: ["metrics", "drift", symbol],
    queryFn: () => metricsApi.getDrift(symbol),
    enabled: !!symbol,
  });

export const useAllDriftMetrics = () =>
  useQuery({
    queryKey: ["metrics", "drift"],
    queryFn: metricsApi.getAllDrift,
  });

export const useModelMetrics = () =>
  useQuery({
    queryKey: ["metrics", "models"],
    queryFn: metricsApi.getModels,
  });

export const useMetricsSummary = () =>
  useQuery({
    queryKey: ["metrics", "summary"],
    queryFn: metricsApi.getSummary,
  });

// ---- Models ----

export const useModels = (stage?: string) =>
  useQuery({
    queryKey: ["models", stage],
    queryFn: () => modelsApi.getAll(stage),
  });

export const useModelDetails = (modelName: string) =>
  useQuery({
    queryKey: ["models", modelName],
    queryFn: () => modelsApi.getDetails(modelName),
    enabled: !!modelName,
  });

export const useModelVersions = (modelName: string) =>
  useQuery({
    queryKey: ["models", modelName, "versions"],
    queryFn: () => modelsApi.getVersions(modelName),
    enabled: !!modelName,
  });

export const useDeployModel = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      modelName,
      version,
      stage,
    }: {
      modelName: string;
      version: string;
      stage?: string;
    }) => modelsApi.deploy(modelName, version, stage),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["models"] });
    },
  });
};

// ---- Features ----

export const useFeatures = (entity?: string) =>
  useQuery({
    queryKey: ["features", entity],
    queryFn: () => featuresApi.getAll(entity),
  });

export const useFeaturesBySymbol = (symbol: string, hours = 24) =>
  useQuery({
    queryKey: ["features", symbol, hours],
    queryFn: () => featuresApi.getBySymbol(symbol, hours),
    enabled: !!symbol,
  });

export const useLatestFeatures = (symbol: string) =>
  useQuery({
    queryKey: ["features", symbol, "latest"],
    queryFn: () => featuresApi.getLatest(symbol),
    enabled: !!symbol,
  });

export const useFeatureStatistics = (symbol: string) =>
  useQuery({
    queryKey: ["features", "statistics", symbol],
    queryFn: () => featuresApi.getStatistics(symbol),
    enabled: !!symbol,
  });

// ---- Symbols ----

export const useSymbols = () =>
  useQuery({
    queryKey: ["symbols"],
    queryFn: symbolsApi.getAll,
  });
