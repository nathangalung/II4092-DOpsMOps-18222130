import React from "react";
import { MetricsChart } from "../components/charts/MetricsChart";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "../components/ui/card";
import { Badge } from "../components/ui/badge";
import { Skeleton } from "../components/ui/skeleton";
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from "../components/ui/table";
import {
  useAllDriftMetrics,
  useModelMetrics,
  useQualityMetrics,
} from "../hooks/queries";
import { formatNumber, formatDate } from "../utils/format";
import { AlertTriangle, CheckCircle } from "lucide-react";
import { cn } from "../lib/utils";
import type { DriftMetrics, ModelMetrics } from "../types";

export const Monitoring: React.FC = () => {
  const { data: driftRes, isLoading: driftLoading } = useAllDriftMetrics();
  const { data: modelRes, isLoading: modelLoading } = useModelMetrics();
  const { data: qualityRes, isLoading: qualityLoading } = useQualityMetrics();

  const driftMetrics: DriftMetrics[] = driftRes?.data || [];
  const modelMetrics: ModelMetrics[] = modelRes || [];
  const qualityMetrics: Record<string, any> = qualityRes || {};
  const loading = driftLoading || modelLoading || qualityLoading;

  const qualityChartData = Object.entries(qualityMetrics).map(
    ([symbol, metrics]: [string, any]) => ({
      name: symbol,
      value: metrics?.completeness || 0,
      status:
        (metrics?.completeness || 0) >= 99
          ? ("good" as const)
          : ("warning" as const),
    }),
  );

  const modelChartData = modelMetrics.map((m) => ({
    name: m.model_name,
    value: m.predictions_count,
    status: "good" as const,
  }));

  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Monitoring</h1>
        <p className="text-gray-500 mt-1">
          Data quality and model drift monitoring
        </p>
      </div>

      {loading ? (
        <div className="space-y-8">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {Array.from({ length: 3 }).map((_, i) => (
              <Skeleton key={i} className="h-48 rounded-xl" />
            ))}
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <Skeleton className="h-80 rounded-xl" />
            <Skeleton className="h-80 rounded-xl" />
          </div>
          <Skeleton className="h-64 rounded-xl" />
        </div>
      ) : (
        <>
          {/* Drift Status */}
          <div>
            <h2 className="text-lg font-semibold text-gray-900 mb-4">
              Drift Detection
            </h2>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {driftMetrics.map((drift) => (
                <Card
                  key={drift.symbol}
                  className={cn(
                    drift.drift_detected ? "border-red-300" : "border-gray-200",
                  )}
                >
                  <CardContent className="p-6">
                    <div className="flex items-start justify-between">
                      <div>
                        <h3 className="font-semibold text-gray-900">
                          {drift.symbol}
                        </h3>
                        <p className="text-sm text-muted-foreground mt-1">
                          PSI: {formatNumber(drift.psi, 3)}
                        </p>
                        {drift.ks_statistic && (
                          <p className="text-sm text-muted-foreground">
                            K-S: {formatNumber(drift.ks_statistic, 3)}
                          </p>
                        )}
                      </div>
                      {drift.drift_detected ? (
                        <div className="p-2 bg-red-100 rounded-lg">
                          <AlertTriangle className="h-5 w-5 text-red-600" />
                        </div>
                      ) : (
                        <div className="p-2 bg-green-100 rounded-lg">
                          <CheckCircle className="h-5 w-5 text-green-600" />
                        </div>
                      )}
                    </div>
                    {drift.drifted_features.length > 0 && (
                      <div className="mt-4">
                        <p className="text-xs text-muted-foreground uppercase">
                          Drifted Features
                        </p>
                        <div className="flex flex-wrap gap-1 mt-1">
                          {drift.drifted_features.map((f) => (
                            <Badge
                              key={f}
                              className="bg-red-100 text-red-800 border-transparent text-xs"
                            >
                              {f}
                            </Badge>
                          ))}
                        </div>
                      </div>
                    )}
                    <p className="text-xs text-muted-foreground mt-4">
                      Last checked: {formatDate(drift.last_checked)}
                    </p>
                  </CardContent>
                </Card>
              ))}
            </div>
          </div>

          {/* Charts */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <MetricsChart
              data={qualityChartData}
              title="Data Completeness by Symbol"
            />
            <MetricsChart data={modelChartData} title="Predictions by Model" />
          </div>

          {/* Model Performance */}
          <div>
            <h2 className="text-lg font-semibold text-gray-900 mb-4">
              Model Performance
            </h2>
            <Card>
              <CardContent className="p-0">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Model</TableHead>
                      <TableHead>Version</TableHead>
                      <TableHead className="text-right">MAE</TableHead>
                      <TableHead className="text-right">RMSE</TableHead>
                      <TableHead className="text-right">Predictions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {modelMetrics.map((model) => (
                      <TableRow key={model.model_name}>
                        <TableCell className="font-medium">
                          {model.model_name}
                        </TableCell>
                        <TableCell>
                          <Badge className="bg-blue-100 text-blue-800 border-transparent">
                            {model.version}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-right">
                          {model.mae ? formatNumber(model.mae, 4) : "-"}
                        </TableCell>
                        <TableCell className="text-right">
                          {model.rmse ? formatNumber(model.rmse, 4) : "-"}
                        </TableCell>
                        <TableCell className="text-right">
                          {formatNumber(model.predictions_count, 0)}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          </div>
        </>
      )}
    </div>
  );
};
