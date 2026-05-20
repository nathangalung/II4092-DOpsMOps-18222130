import { useEffect, useRef, useState, useCallback } from "react";
import { useAuth } from "../context/AuthContext";

interface WebSocketMessage {
  type: string;
  channel?: string;
  data?: unknown;
  timestamp?: string;
  message?: string;
}

interface UseWebSocketOptions {
  channels?: string[];
  onMessage?: (message: WebSocketMessage) => void;
  reconnectAttempts?: number;
  reconnectInterval?: number;
}

interface UseWebSocketResult {
  isConnected: boolean;
  lastMessage: WebSocketMessage | null;
  sendMessage: (message: object) => void;
  subscribe: (channel: string) => void;
  unsubscribe: (channel: string) => void;
}

export function useWebSocket(
  options: UseWebSocketOptions = {},
): UseWebSocketResult {
  const { token } = useAuth();
  const [isConnected, setIsConnected] = useState(false);
  const [lastMessage, setLastMessage] = useState<WebSocketMessage | null>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectAttemptsRef = useRef(0);

  const {
    channels = ["predictions", "data"],
    onMessage,
    reconnectAttempts = 5,
    reconnectInterval = 3000,
  } = options;

  const connect = useCallback(() => {
    if (!token) return;

    const wsUrl = `ws://${window.location.host}/ws?token=${token}&channels=${channels.join(",")}`;
    const ws = new WebSocket(wsUrl);

    ws.onopen = () => {
      setIsConnected(true);
      reconnectAttemptsRef.current = 0;
    };

    ws.onmessage = (event) => {
      try {
        const message: WebSocketMessage = JSON.parse(event.data);
        setLastMessage(message);
        onMessage?.(message);
      } catch {
        console.error("Failed to parse WebSocket message");
      }
    };

    ws.onclose = () => {
      setIsConnected(false);

      if (reconnectAttemptsRef.current < reconnectAttempts) {
        reconnectAttemptsRef.current += 1;
        setTimeout(connect, reconnectInterval);
      }
    };

    ws.onerror = () => {
      ws.close();
    };

    wsRef.current = ws;
  }, [token, channels, onMessage, reconnectAttempts, reconnectInterval]);

  useEffect(() => {
    connect();
    return () => {
      wsRef.current?.close();
    };
  }, [connect]);

  const sendMessage = useCallback((message: object) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify(message));
    }
  }, []);

  const subscribe = useCallback(
    (channel: string) => {
      sendMessage({ type: "subscribe", channel });
    },
    [sendMessage],
  );

  const unsubscribe = useCallback(
    (channel: string) => {
      sendMessage({ type: "unsubscribe", channel });
    },
    [sendMessage],
  );

  return {
    isConnected,
    lastMessage,
    sendMessage,
    subscribe,
    unsubscribe,
  };
}
