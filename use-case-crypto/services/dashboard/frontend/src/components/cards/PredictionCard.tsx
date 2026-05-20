import React from "react";
import { Card, CardContent } from "../ui/card";
import { Badge } from "../ui/badge";
import { cn } from "../../lib/utils";
import { PREDICTION_VALUE_LABEL } from "../../config/domain";
import {
  getClassColor,
  getClassLabel,
  formatNumber,
  formatPercent,
} from "../../utils/format";
import type { Prediction } from "../../types";

interface PredictionCardProps {
  prediction: Prediction;
  className?: string;
}

export const PredictionCard: React.FC<PredictionCardProps> = ({
  prediction,
  className,
}) => {
  return (
    <Card className={cn("p-6", className)}>
      <CardContent className="p-0">
        <div className="flex items-start justify-between">
          <div>
            <p className="text-lg font-semibold text-foreground">
              {prediction.symbol}
            </p>
            <p className="text-2xl font-bold text-foreground mt-2">
              {formatNumber(prediction.predicted_value)}
            </p>
            <p className="text-sm text-muted-foreground mt-1">
              {PREDICTION_VALUE_LABEL}
            </p>
          </div>
          <div className="text-right">
            <Badge
              className={cn(
                "px-3 py-1 text-sm font-bold",
                getClassColor(prediction.class_index),
              )}
            >
              {getClassLabel(prediction.class_index)}
            </Badge>
            <p className="text-sm text-muted-foreground mt-2">
              Confidence: {formatPercent(prediction.confidence)}
            </p>
          </div>
        </div>
        {prediction.model_version && (
          <p className="text-xs text-muted-foreground mt-4">
            Model: {prediction.model_version}
          </p>
        )}
      </CardContent>
    </Card>
  );
};
