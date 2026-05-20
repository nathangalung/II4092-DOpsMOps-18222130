import { format, formatDistanceToNow } from "date-fns";
import { CLASS_COLORS, CLASS_LABELS } from "../config/domain";

export const formatCurrency = (value: number, decimals = 2): string => {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(value);
};

export const formatNumber = (value: number, decimals = 2): string => {
  return new Intl.NumberFormat("en-US", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(value);
};

export const formatPercent = (value: number, decimals = 2): string => {
  return `${(value * 100).toFixed(decimals)}%`;
};

export const formatDate = (date: string | Date): string => {
  return format(new Date(date), "MMM d, yyyy HH:mm");
};

export const formatRelativeTime = (date: string | Date): string => {
  return formatDistanceToNow(new Date(date), { addSuffix: true });
};

export const getClassColor = (classIndex: number): string => {
  return CLASS_COLORS[classIndex] ?? "text-gray-600 bg-gray-100";
};

export const getClassLabel = (classIndex: number): string => {
  return CLASS_LABELS[classIndex] ?? `Class ${classIndex}`;
};

export const getRoleLabel = (role: string): string => {
  const labels: Record<string, string> = {
    data_engineer: "Data Engineer",
    data_scientist: "Data Scientist",
    ml_engineer: "ML Engineer",
    business_user: "Business User",
  };
  return labels[role] || role;
};

export const getRoleColor = (role: string): string => {
  const colors: Record<string, string> = {
    data_engineer: "bg-blue-100 text-blue-800",
    data_scientist: "bg-purple-100 text-purple-800",
    ml_engineer: "bg-green-100 text-green-800",
    business_user: "bg-gray-100 text-gray-800",
  };
  return colors[role] || "bg-gray-100 text-gray-800";
};
