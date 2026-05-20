import React from "react";
import { Card, CardContent } from "../ui/card";
import { cn } from "../../lib/utils";

interface MetricCardProps {
  title: string;
  value: string | number;
  subtitle?: string;
  icon?: React.ReactNode;
  trend?: {
    value: number;
    isPositive: boolean;
  };
  className?: string;
}

export const MetricCard: React.FC<MetricCardProps> = ({
  title,
  value,
  subtitle,
  icon,
  trend,
  className,
}) => {
  return (
    <Card className={cn("p-6", className)}>
      <CardContent className="p-0">
        <div className="flex items-start justify-between">
          <div>
            <p className="text-sm font-medium text-muted-foreground">{title}</p>
            <p className="text-2xl font-bold text-foreground mt-2">{value}</p>
            {subtitle && (
              <p className="text-sm text-muted-foreground mt-1">{subtitle}</p>
            )}
            {trend && (
              <div
                className={cn(
                  "flex items-center gap-1 mt-2 text-sm font-medium",
                  trend.isPositive ? "text-green-600" : "text-red-600",
                )}
              >
                <span>
                  {trend.isPositive ? "+" : ""}
                  {trend.value}%
                </span>
                <span className="text-muted-foreground">vs last hour</span>
              </div>
            )}
          </div>
          {icon && <div className="p-3 bg-primary-50 rounded-lg">{icon}</div>}
        </div>
      </CardContent>
    </Card>
  );
};
