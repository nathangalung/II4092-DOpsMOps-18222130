// Crypto-specific domain configuration — BUY/SELL/HOLD trading signals.

export const CLASS_LABELS: Record<number, string> = {
  1: "BUY",
  0: "HOLD",
  [-1]: "SELL",
};

export const CLASS_COLORS: Record<number, string> = {
  1: "text-green-600 bg-green-100",
  0: "text-gray-600 bg-gray-100",
  [-1]: "text-red-600 bg-red-100",
};

export const PREDICTION_VALUE_LABEL = "Predicted Price";

export const MOCK_BASE_VALUE = 43000;
export const MOCK_VARIANCE = 2000;
