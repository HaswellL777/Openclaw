export type ConnectionState = "connecting" | "connected" | "disconnected";
export type EventCallback = (params: any) => void;
export type ConnectionCallback = (state: ConnectionState) => void;

interface RpcRequest {
  jsonrpc: "2.0";
  method: string;
  params?: any;
  id: number;
}

interface RpcResponse {
  jsonrpc: "2.0";
  result?: any;
  error?: { code: number; message: string };
  id: number;
}

interface RpcEvent {
  jsonrpc: "2.0";
  method: string;
  params?: any;
  // no id = server push
}

interface PendingRequest {
  resolve: (value: any) => void;
  reject: (reason: any) => void;
  timer: ReturnType<typeof setTimeout>;
}

const DEFAULT_TIMEOUT_MS = 30_000;
const MAX_RECONNECT_DELAY_MS = 30_000;
const INITIAL_RECONNECT_DELAY_MS = 500;

export class RpcClient {
  private url: string;
  private ws: WebSocket | null = null;
  private state: ConnectionState = "disconnected";
  private nextId = 1;
  private pending = new Map<number, PendingRequest>();
  private eventListeners = new Map<string, Set<EventCallback>>();
  private connectionListeners = new Set<ConnectionCallback>();
  private reconnectDelay = INITIAL_RECONNECT_DELAY_MS;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private intentionalClose = false;

  constructor(url: string) {
    this.url = url;
  }

  connect(): void {
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      return;
    }

    this.intentionalClose = false;
    this.setState("connecting");

    try {
      this.ws = new WebSocket(this.url);
    } catch {
      this.setState("disconnected");
      this.scheduleReconnect();
      return;
    }

    this.ws.onopen = () => {
      this.setState("connected");
      this.reconnectDelay = INITIAL_RECONNECT_DELAY_MS;
    };

    this.ws.onmessage = (event) => {
      this.handleMessage(event.data);
    };

    this.ws.onclose = () => {
      this.setState("disconnected");
      this.rejectAllPending("Connection closed");
      if (!this.intentionalClose) {
        this.scheduleReconnect();
      }
    };

    this.ws.onerror = () => {
      // onclose will fire after onerror, so reconnect is handled there
    };
  }

  disconnect(): void {
    this.intentionalClose = true;

    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }

    this.rejectAllPending("Client disconnected");
    this.setState("disconnected");
  }

  call<T = any>(method: string, params?: any, timeoutMs: number = DEFAULT_TIMEOUT_MS): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      if (this.state !== "connected" || !this.ws) {
        reject(new Error("Not connected"));
        return;
      }

      const id = this.nextId++;

      const timer = setTimeout(() => {
        const req = this.pending.get(id);
        if (req) {
          this.pending.delete(id);
          req.reject(new Error(`RPC timeout after ${timeoutMs}ms: ${method}`));
        }
      }, timeoutMs);

      this.pending.set(id, { resolve, reject, timer });

      const request: RpcRequest = {
        jsonrpc: "2.0",
        method,
        params,
        id,
      };

      try {
        this.ws.send(JSON.stringify(request));
      } catch (err) {
        clearTimeout(timer);
        this.pending.delete(id);
        reject(err);
      }
    });
  }

  on(event: string, callback: EventCallback): () => void {
    let listeners = this.eventListeners.get(event);
    if (!listeners) {
      listeners = new Set();
      this.eventListeners.set(event, listeners);
    }
    listeners.add(callback);

    return () => {
      listeners!.delete(callback);
      if (listeners!.size === 0) {
        this.eventListeners.delete(event);
      }
    };
  }

  onConnectionChange(callback: ConnectionCallback): () => void {
    this.connectionListeners.add(callback);
    // Immediately notify with current state
    callback(this.state);
    return () => {
      this.connectionListeners.delete(callback);
    };
  }

  getState(): ConnectionState {
    return this.state;
  }

  private setState(newState: ConnectionState): void {
    if (this.state === newState) return;
    this.state = newState;
    for (const cb of this.connectionListeners) {
      try {
        cb(newState);
      } catch {
        // listener errors must not break state machine
      }
    }
  }

  private handleMessage(data: string | ArrayBuffer | Blob): void {
    if (typeof data !== "string") return;

    let msg: RpcResponse | RpcEvent;
    try {
      msg = JSON.parse(data);
    } catch {
      return;
    }

    if (msg.jsonrpc !== "2.0") return;

    // Response to a pending request (has numeric id)
    if ("id" in msg && typeof (msg as RpcResponse).id === "number") {
      const resp = msg as RpcResponse;
      const req = this.pending.get(resp.id);
      if (!req) return;

      this.pending.delete(resp.id);
      clearTimeout(req.timer);

      if (resp.error) {
        req.reject(new Error(`RPC error ${resp.error.code}: ${resp.error.message}`));
      } else {
        req.resolve(resp.result);
      }
      return;
    }

    // Server-push event (has method, no id)
    if ("method" in msg && !("id" in msg)) {
      const evt = msg as RpcEvent;
      const listeners = this.eventListeners.get(evt.method);
      if (listeners) {
        for (const cb of listeners) {
          try {
            cb(evt.params);
          } catch {
            // listener errors must not break event dispatch
          }
        }
      }
    }
  }

  private scheduleReconnect(): void {
    if (this.reconnectTimer !== null) return;

    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.connect();
    }, this.reconnectDelay);

    // Exponential backoff capped at max
    this.reconnectDelay = Math.min(this.reconnectDelay * 2, MAX_RECONNECT_DELAY_MS);
  }

  private rejectAllPending(reason: string): void {
    for (const [id, req] of this.pending) {
      clearTimeout(req.timer);
      req.reject(new Error(reason));
      this.pending.delete(id);
    }
  }
}
