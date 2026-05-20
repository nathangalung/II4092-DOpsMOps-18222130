import { describe, it, expect } from "vitest";
import {
  formatCurrency,
  formatNumber,
  formatPercent,
  formatDate,
  formatRelativeTime,
  getClassColor,
  getClassLabel,
  getRoleLabel,
  getRoleColor,
} from "./format";

describe("format utilities", () => {
  describe("formatCurrency", () => {
    it("should format positive numbers as currency", () => {
      expect(formatCurrency(1234.56)).toBe("$1,234.56");
      expect(formatCurrency(0.99)).toBe("$0.99");
    });

    it("should format zero", () => {
      expect(formatCurrency(0)).toBe("$0.00");
    });

    it("should format large numbers", () => {
      expect(formatCurrency(1000000)).toBe("$1,000,000.00");
      expect(formatCurrency(1000.123)).toBe("$1,000.12");
    });

    it("should respect decimal precision", () => {
      expect(formatCurrency(1234.5678, 4)).toBe("$1,234.5678");
      expect(formatCurrency(1234.5, 0)).toBe("$1,235");
    });

    it("should handle negative values", () => {
      expect(formatCurrency(-100.5)).toBe("-$100.50");
    });
  });

  describe("formatNumber", () => {
    it("should format numbers with default precision", () => {
      expect(formatNumber(1234.5678)).toBe("1,234.57");
      expect(formatNumber(0)).toBe("0.00");
    });

    it("should format large numbers with commas", () => {
      expect(formatNumber(1000000)).toBe("1,000,000.00");
    });

    it("should respect decimal precision", () => {
      expect(formatNumber(1234.5678, 3)).toBe("1,234.568");
      expect(formatNumber(1234.5, 0)).toBe("1,235");
    });

    it("should handle negative numbers", () => {
      expect(formatNumber(-1234.56)).toBe("-1,234.56");
    });

    it("should handle very small numbers", () => {
      expect(formatNumber(0.00001, 5)).toBe("0.00001");
    });
  });

  describe("formatPercent", () => {
    it("should format decimal values as percentages", () => {
      expect(formatPercent(0.1234)).toBe("12.34%");
      expect(formatPercent(1)).toBe("100.00%");
      expect(formatPercent(0)).toBe("0.00%");
    });

    it("should handle negative percentages", () => {
      expect(formatPercent(-0.05)).toBe("-5.00%");
    });

    it("should respect decimal precision", () => {
      expect(formatPercent(0.123456, 4)).toBe("12.3456%");
      expect(formatPercent(0.5, 0)).toBe("50%");
    });

    it("should handle values greater than 1", () => {
      expect(formatPercent(2.5)).toBe("250.00%");
    });
  });

  describe("formatDate", () => {
    it("should format Date objects", () => {
      const date = new Date("2024-01-15T10:30:00Z");
      const result = formatDate(date);
      expect(result).toMatch(/Jan 15, 2024/);
    });

    it("should format date strings", () => {
      const result = formatDate("2024-12-25T12:00:00Z");
      expect(result).toMatch(/Dec 25, 2024/);
    });

    it("should handle different time zones", () => {
      const date = "2024-01-01T00:00:00Z";
      const result = formatDate(date);
      expect(result).toBeTruthy();
    });
  });

  describe("formatRelativeTime", () => {
    it("should format recent dates", () => {
      const now = new Date();
      const result = formatRelativeTime(now);
      expect(result).toMatch(/less than a minute ago|seconds ago/);
    });

    it("should format dates in the past", () => {
      const pastDate = new Date();
      pastDate.setHours(pastDate.getHours() - 2);
      const result = formatRelativeTime(pastDate);
      expect(result).toMatch(/2 hours ago|about 2 hours ago/);
    });

    it("should handle date strings", () => {
      const pastDate = new Date();
      pastDate.setDate(pastDate.getDate() - 1);
      const result = formatRelativeTime(pastDate.toISOString());
      expect(result).toMatch(/1 day ago|about 1 day ago/);
    });
  });

  describe("getClassColor", () => {
    it("should return green for positive class", () => {
      expect(getClassColor(1)).toBe("text-green-600 bg-green-100");
    });

    it("should return red for negative class", () => {
      expect(getClassColor(-1)).toBe("text-red-600 bg-red-100");
    });

    it("should return gray for neutral class", () => {
      expect(getClassColor(0)).toBe("text-gray-600 bg-gray-100");
    });

    it("should handle unknown class values", () => {
      expect(getClassColor(5)).toBe("text-gray-600 bg-gray-100");
      expect(getClassColor(-5)).toBe("text-gray-600 bg-gray-100");
    });
  });

  describe("getClassLabel", () => {
    it("should return POSITIVE for class 1", () => {
      expect(getClassLabel(1)).toBe("POSITIVE");
    });

    it("should return NEGATIVE for class -1", () => {
      expect(getClassLabel(-1)).toBe("NEGATIVE");
    });

    it("should return NEUTRAL for class 0", () => {
      expect(getClassLabel(0)).toBe("NEUTRAL");
    });

    it("should return fallback for unknown classes", () => {
      expect(getClassLabel(100)).toBe("Class 100");
      expect(getClassLabel(-100)).toBe("Class -100");
    });
  });

  describe("getRoleLabel", () => {
    it("should return formatted labels for known roles", () => {
      expect(getRoleLabel("data_engineer")).toBe("Data Engineer");
      expect(getRoleLabel("data_scientist")).toBe("Data Scientist");
      expect(getRoleLabel("ml_engineer")).toBe("ML Engineer");
      expect(getRoleLabel("business_user")).toBe("Business User");
    });

    it("should return the role as-is for unknown roles", () => {
      expect(getRoleLabel("custom_role")).toBe("custom_role");
      expect(getRoleLabel("admin")).toBe("admin");
    });

    it("should handle empty string", () => {
      expect(getRoleLabel("")).toBe("");
    });
  });

  describe("getRoleColor", () => {
    it("should return colors for known roles", () => {
      expect(getRoleColor("data_engineer")).toBe("bg-blue-100 text-blue-800");
      expect(getRoleColor("data_scientist")).toBe(
        "bg-purple-100 text-purple-800",
      );
      expect(getRoleColor("ml_engineer")).toBe("bg-green-100 text-green-800");
      expect(getRoleColor("business_user")).toBe("bg-gray-100 text-gray-800");
    });

    it("should return default color for unknown roles", () => {
      expect(getRoleColor("unknown")).toBe("bg-gray-100 text-gray-800");
      expect(getRoleColor("")).toBe("bg-gray-100 text-gray-800");
    });
  });
});
