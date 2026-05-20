import React, { useState, useEffect } from "react";
import { PredictionCard } from "../components/cards/PredictionCard";
import { TimeSeriesChart } from "../components/charts/TimeSeriesChart";
import { Skeleton } from "../components/ui/skeleton";
import { Badge } from "../components/ui/badge";
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from "../components/ui/table";
import {
  Card,
  CardHeader,
  CardTitle,
  CardContent,
} from "../components/ui/card";
import {
  useSymbols,
  useLatestPrediction,
  usePredictionsBySymbol,
} from "../hooks/queries";
import { PREDICTION_VALUE_LABEL } from "../config/domain";
import { formatDate, getClassColor, getClassLabel } from "../utils/format";

export const Predictions: React.FC = () => {
  const [selectedSymbol, setSelectedSymbol] = useState<string>("");

  const { data: symbolsRes } = useSymbols();
  const symbols: string[] = symbolsRes?.data || ["SYMBOL-1", "SYMBOL-2"];

  useEffect(() => {
    if (symbols.length > 0 && !selectedSymbol) {
      setSelectedSymbol(symbols[0]);
    }
  }, [symbols, selectedSymbol]);

  const { data: latestPrediction, isLoading: latestLoading } =
    useLatestPrediction(selectedSymbol);
  const { data: historyRes, isLoading: historyLoading } =
    usePredictionsBySymbol(selectedSymbol, 24);

  const predictions = historyRes?.data || [];
  const loading = latestLoading || historyLoading;

  const chartData = predictions.map((p: any) => ({
    timestamp: p.timestamp,
    price: p.predicted_value,
    predicted: p.predicted_value,
  }));

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Predictions</h1>
          <p className="text-gray-500 mt-1">
            View model predictions and classifications
          </p>
        </div>

        {/* Symbol Selector */}
        <select
          value={selectedSymbol}
          onChange={(e) => setSelectedSymbol(e.target.value)}
          className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-primary-500 focus:border-primary-500"
        >
          {symbols.map((symbol) => (
            <option key={symbol} value={symbol}>
              {symbol}
            </option>
          ))}
        </select>
      </div>

      {loading ? (
        <div className="space-y-8">
          <Skeleton className="h-40 w-96 rounded-xl" />
          <Skeleton className="h-96 rounded-xl" />
          <Skeleton className="h-64 rounded-xl" />
        </div>
      ) : (
        <>
          {/* Latest Prediction */}
          {latestPrediction && (
            <div className="max-w-md">
              <h2 className="text-lg font-semibold text-gray-900 mb-4">
                Current Prediction
              </h2>
              <PredictionCard prediction={latestPrediction} />
            </div>
          )}

          {/* Prediction Chart */}
          <TimeSeriesChart data={chartData} showPredicted={false} />

          {/* Prediction History Table */}
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Prediction History</CardTitle>
            </CardHeader>
            <CardContent>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Timestamp</TableHead>
                    <TableHead>{PREDICTION_VALUE_LABEL}</TableHead>
                    <TableHead>Classification</TableHead>
                    <TableHead>Confidence</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {predictions.slice(0, 10).map((pred: any, idx: number) => (
                    <TableRow key={idx}>
                      <TableCell className="text-sm">
                        {formatDate(pred.timestamp)}
                      </TableCell>
                      <TableCell className="text-sm">
                        {pred.predicted_value?.toFixed(2)}
                      </TableCell>
                      <TableCell>
                        <Badge className={getClassColor(pred.class_index)}>
                          {getClassLabel(pred.class_index)}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-sm">
                        {(pred.confidence * 100).toFixed(1)}%
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
};
