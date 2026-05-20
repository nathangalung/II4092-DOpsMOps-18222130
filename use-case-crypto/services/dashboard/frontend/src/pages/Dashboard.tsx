import React from "react";
import { TrendingUp, Database, Box, Activity } from "lucide-react";
import { MetricCard } from "../components/cards/MetricCard";
import { PredictionCard } from "../components/cards/PredictionCard";
import { TimeSeriesChart } from "../components/charts/TimeSeriesChart";
import { Skeleton } from "../components/ui/skeleton";
import { MOCK_BASE_VALUE, MOCK_VARIANCE } from "../config/domain";
import { usePredictions, useSystemMetrics } from "../hooks/queries";
import { formatNumber, formatPercent } from "../utils/format";
import type { Prediction } from "../types";

export const Dashboard: React.FC = () => {
  const { data: predictionsRes, isLoading: predictionsLoading } =
    usePredictions();
  const { data: systemMetrics, isLoading: metricsLoading } = useSystemMetrics();

  const predictions: Prediction[] = predictionsRes?.data || [];
  const loading = predictionsLoading || metricsLoading;

  // Generate mock data for chart
  const priceData = React.useMemo(
    () =>
      Array.from({ length: 24 }, (_, i) => ({
        timestamp: new Date(Date.now() - (23 - i) * 3600000).toISOString(),
        price: MOCK_BASE_VALUE + Math.random() * MOCK_VARIANCE,
        predicted: MOCK_BASE_VALUE + Math.random() * MOCK_VARIANCE,
      })),
    [],
  );

  if (loading) {
    return (
      <div className="space-y-8">
        <div>
          <Skeleton className="h-8 w-48" />
          <Skeleton className="h-4 w-72 mt-2" />
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-32 rounded-xl" />
          ))}
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-40 rounded-xl" />
          ))}
        </div>
        <Skeleton className="h-96 rounded-xl" />
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
        <p className="text-gray-500 mt-1">
          Overview of your ML pipeline platform
        </p>
      </div>

      {/* System Metrics */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <MetricCard
          title="Ingestion Rate"
          value={`${formatNumber(systemMetrics?.ingestion_rate || 0)} /s`}
          subtitle="Records per second"
          icon={<Database className="h-6 w-6 text-primary-600" />}
        />
        <MetricCard
          title="Processing Latency"
          value={`${formatNumber(systemMetrics?.processing_latency_ms || 0)} ms`}
          subtitle="Average processing time"
          icon={<Activity className="h-6 w-6 text-primary-600" />}
        />
        <MetricCard
          title="Prediction Latency"
          value={`${formatNumber(systemMetrics?.prediction_latency_ms || 0)} ms`}
          subtitle="Average prediction time"
          icon={<TrendingUp className="h-6 w-6 text-primary-600" />}
        />
        <MetricCard
          title="Cache Hit Rate"
          value={formatPercent(systemMetrics?.cache_hit_rate || 0)}
          subtitle={`${systemMetrics?.active_models || 0} active models`}
          icon={<Box className="h-6 w-6 text-primary-600" />}
        />
      </div>

      {/* Predictions */}
      <div>
        <h2 className="text-lg font-semibold text-gray-900 mb-4">
          Latest Predictions
        </h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {predictions.length > 0 ? (
            predictions.map((pred) => (
              <PredictionCard key={pred.symbol} prediction={pred} />
            ))
          ) : (
            <div className="col-span-full text-center py-8 text-gray-500">
              No predictions available
            </div>
          )}
        </div>
      </div>

      {/* Time Series Chart */}
      <TimeSeriesChart data={priceData} />
    </div>
  );
};
