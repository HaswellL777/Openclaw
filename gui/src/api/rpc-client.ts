export type ConnectionState = "connecting" | "connected" | "disconnected";
export type EventCallback = (params: any) => void;
export type ConnectionCallback = (state: ConnectionState) => void;

interface PendingRequest {
  resolve: (value: any) => void;
  reject: (reason: any) => void;
  timer: ReturnType<typeof setTimeout>;
}

const DEFAULT_TIMEOUT_MS = 30_000;
const MAX_RECONNECT_DELAY_MS = 30_000;
const INITIAL_RECONNECT_DELAY_MS = 500;

/**
 * OpenClaw Gateway WebSocket client.
 *
 * Protocol:
 * 1. Client opens WebSocket
 * 2. Server sends { type: "event", event: "connect.challenge", payload: { nonce, ts } }
 * 3. Client sends { type: "req", method: "connect", id, params: { client, minProtocol, maxProtocol, role, auth } }
 * 4. Server sends { type: "res", id, ok: true, result: {...} } → connected
 * 5. After handshake: RPC via { type: "req", method, id, params } / { type: "res", id, ok, result/error }
 *    Server pushes: { type: "event", event: "...", payload: {...} }
 */
export class RpcClient {
  private url: string;
  private token: string | undefined;
  private ws: WebSocket | null = null;
  private state: ConnectionState = "disconnected";
  private nextId = 1;
  private pending = new Map<number, PendingRequest>();
  private eventListeners = new Map<string, Set<EventCallback>>();
  private connectionListeners = new Set<ConnectionCallback>();
  private reconnectDelay = INITIAL_RECONNECT_DELAY_MS;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private intentionalClose = false;
  private handshakeComplete = false;

  constructor(url: string, token?: string) {
    this.url = url;
    this.token = token;
  }

  connect(): void {
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      return;
    }

    this.intentionalClose = false;
    this.handshakeComplete = false;
    this.setState("connecting");

    try {
      this.ws = new WebSocket(this.url);
    } catch {
      this.setState("disconnected");
      this.scheduleReconnect();
      return;
    }

    this.ws.onopen = () => {
      // Don't set connected yet — wait for handshake completion
    };

    this.ws.onmessage = (event) => {
      this.handleMessage(event.data);
    };

    this.ws.onclose = () => {
      this.handshakeComplete = false;
      this.setState("disconnected");
      this.rejectAllPending("Connection closed");
      if (!this.intentionalClose) {
        this.scheduleReconnect();
      }
    };

    this.ws.onerror = () => {
      // onclose will fire after onerror
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

    this.handshakeComplete = false;
    this.rejectAllPending("Client disconnected");
    this.setState("disconnected");
  }

  call<T = any>(method: string, params?: any, timeoutMs: number = DEFAULT_TIMEOUT_MS): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      if (!this.handshakeComplete || !this.ws) {
        reject(new Error("Not connected"));
        return;
      }

      const id = String(this.nextId++);

      const timer = setTimeout(() => {
        const req = this.pending.get(Number(id));
        if (req) {
          this.pending.delete(Number(id));
          req.reject(new Error(`RPC timeout after ${timeoutMs}ms: ${method}`));
        }
      }, timeoutMs);

      this.pending.set(Number(id), { resolve, reject, timer });

      const frame = { type: "req", method, id, params: params ?? {} };

      try {
        this.ws.send(JSON.stringify(frame));
      } catch (err) {
        clearTimeout(timer);
        this.pending.delete(Number(id));
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
      const current = this.eventListeners.get(event);
      if (current) {
        current.delete(callback);
        if (current.size === 0) {
          this.eventListeners.delete(event);
        }
      }
    };
  }

  onConnectionChange(callback: ConnectionCallback): () => void {
    this.connectionListeners.add(callback);
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
      try { cb(newState); } catch { /* listener errors must not break state machine */ }
    }
  }

  private handleMessage(data: string | ArrayBuffer | Blob): void {
    if (typeof data !== "string") return;

    let msg: any;
    try { msg = JSON.parse(data); } catch { return; }

    // OpenClaw protocol: { type: "event", event: "...", payload: {...} }
    if (msg.type === "event") {
      if (msg.event === "connect.challenge") {
        this.sendConnectHandshake();
        return;
      }
      // After handshake, dispatch events to listeners
      if (msg.event) {
        const listeners = this.eventListeners.get(msg.event);
        if (listeners) {
          for (const cb of listeners) {
            try { cb(msg.payload); } catch { /* swallow */ }
          }
        }
      }
      return;
    }

    // OpenClaw protocol: { type: "res", id: "...", ok: boolean, result/error }
    if (msg.type === "res" && msg.id != null) {
      const numId = typeof msg.id === "string" ? Number(msg.id) : msg.id;
      const req = this.pending.get(numId);
      if (!req) {
        // Could be the connect handshake response
        if (msg.ok && !this.handshakeComplete) {
          this.handshakeComplete = true;
          this.setState("connected");
          this.reconnectDelay = INITIAL_RECONNECT_DELAY_MS;
        } else if (!msg.ok && !this.handshakeComplete) {
          console.error("Gateway handshake failed:", msg.error);
          this.ws?.close();
        }
        return;
      }

      this.pending.delete(numId);
      clearTimeout(req.timer);

      if (msg.ok === false || msg.error) {
        req.reject(new Error(`RPC error: ${msg.error?.message ?? JSON.stringify(msg.error)}`));
      } else {
        req.resolve(msg.result);
      }
      return;
    }

    // Fallback: JSON-RPC 2.0 server-push (method + no id)
    if (msg.jsonrpc === "2.0" && msg.method && !("id" in msg)) {
      const listeners = this.eventListeners.get(msg.method);
      if (listeners) {
        for (const cb of listeners) {
          try { cb(msg.params); } catch { /* swallow */ }
        }
      }
    }
  }

  private sendConnectHandshake(): void {
    if (!this.ws) return;

    const connectId = String(this.nextId++);

    const frame = {
      type: "req",
      method: "connect",
      id: connectId,
      params: {
        client: {
          id: "gateway-client",
          displayName: "OpenClaw GUI",
          mode: "backend",
          version: "0.1.0",
          platform: typeof navigator !== "undefined" ? navigator.platform : "web",
        },
        minProtocol: 3,
        maxProtocol: 3,
        role: "operator",
        scopes: ["read", "write", "admin"],
        ...(this.token ? { auth: { token: this.token } } : {}),
      },
    };

    try {
      this.ws.send(JSON.stringify(frame));
    } catch {
      console.error("Failed to send connect handshake");
    }
  }

  private scheduleReconnect(): void {
    if (this.reconnectTimer !== null) return;

    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.connect();
    }, this.reconnectDelay);

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
