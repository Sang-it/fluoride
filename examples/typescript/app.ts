import { EventEmitter } from "events";

let activeCount = 0;

const MAX_CONNECTIONS = 100;

interface ServerConfig {
  host: string;
  port: number;
  debug?: boolean;
}

type ConnectionState = "idle" | "active" | "closed";

enum LogLevel {
  Debug = "DEBUG",
  Info = "INFO",
  Warn = "WARN",
  Error = "ERROR",
}

class ConnectionPool {
  private connections: Map<string, ConnectionState> = new Map();

  add(id: string): void {
    this.connections.set(id, "idle");
    activeCount++;
  }

  remove(id: string): void {
    this.connections.delete(id);
    activeCount--;
  }

  getActive(): string[] {
    return [...this.connections.entries()]
      .filter(([_, state]) => state === "active")
      .map(([id]) => id);
  }
}

export const DEFAULT_CONFIG: ServerConfig = {
  host: "0.0.0.0",
  port: 8080,
};

function shutdown(pool: ConnectionPool): void {
  const active = pool.getActive();
  active.forEach((id) => pool.remove(id));
}

const parseConfig = (raw: Record<string, unknown>): ServerConfig => {
  return {
    host: String(raw.host ?? "localhost"),
    port: Number(raw.port ?? 3000),
    debug: Boolean(raw.debug),
  };
};

export function startServer(config: ServerConfig): void {
  const log = createLogger(LogLevel.Info);
  log(`Starting server on ${config.host}:${config.port}`);
}

function createLogger(level: LogLevel) {
  return (message: string) => {
    console.log(`[${level}] ${message}`);
  };
}
