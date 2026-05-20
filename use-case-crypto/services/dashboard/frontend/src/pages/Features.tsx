import React, { useState, useEffect } from "react";
import { Skeleton } from "../components/ui/skeleton";
import { Badge } from "../components/ui/badge";
import { Card, CardContent } from "../components/ui/card";
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from "../components/ui/table";
import { useFeatures, useSymbols, useLatestFeatures } from "../hooks/queries";
import { formatNumber } from "../utils/format";
import type { Feature } from "../types";

export const Features: React.FC = () => {
  const [selectedSymbol, setSelectedSymbol] = useState("");

  const { data: featuresRes, isLoading: featuresLoading } = useFeatures();
  const { data: symbolsRes } = useSymbols();
  const symbols: string[] = symbolsRes?.data || ["SYMBOL-1", "SYMBOL-2"];
  const features: Feature[] = featuresRes?.data || [];

  useEffect(() => {
    if (symbols.length > 0 && !selectedSymbol) {
      setSelectedSymbol(symbols[0]);
    }
  }, [symbols, selectedSymbol]);

  const { data: latestRes } = useLatestFeatures(selectedSymbol);
  const featureValues: Record<string, number> = latestRes?.features || {};

  const groupedFeatures = features.reduce(
    (acc, feature) => {
      const tag = feature.tags[0] || "other";
      if (!acc[tag]) acc[tag] = [];
      acc[tag].push(feature);
      return acc;
    },
    {} as Record<string, Feature[]>,
  );

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Feature Store</h1>
          <p className="text-gray-500 mt-1">
            Explore features and their values
          </p>
        </div>

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

      {featuresLoading ? (
        <div className="space-y-8">
          {Array.from({ length: 2 }).map((_, i) => (
            <Skeleton key={i} className="h-64 rounded-xl" />
          ))}
        </div>
      ) : (
        <div className="space-y-8">
          {Object.entries(groupedFeatures).map(([group, groupFeatures]) => (
            <div key={group}>
              <h2 className="text-lg font-semibold text-gray-900 mb-4 capitalize">
                {group} Features
              </h2>
              <Card>
                <CardContent className="p-0">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Feature Name</TableHead>
                        <TableHead>Description</TableHead>
                        <TableHead>Type</TableHead>
                        <TableHead className="text-right">
                          Current Value
                        </TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {groupFeatures.map((feature) => (
                        <TableRow key={feature.name}>
                          <TableCell className="font-medium">
                            {feature.name}
                          </TableCell>
                          <TableCell className="text-sm text-muted-foreground">
                            {feature.description || "-"}
                          </TableCell>
                          <TableCell>
                            <Badge variant="secondary" className="text-xs">
                              {feature.value_type}
                            </Badge>
                          </TableCell>
                          <TableCell className="text-right font-mono text-sm">
                            {featureValues[feature.name] !== undefined
                              ? formatNumber(featureValues[feature.name], 4)
                              : "-"}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </CardContent>
              </Card>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
