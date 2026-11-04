import { clientMessage, serverMessage, type Direction, type Welcome } from "./protocol";

export type ConnectionStatus = "disconnected" | "connecting" | "connected" | "error";
export type Snapshot = {
  status: ConnectionStatus;
  welcome: Welcome | null;
  player: { x: number; y: number } | null;
  tick: number;
  ack: number;
  error: string | null;
};
type SocketFactory = (url: string) => WebSocket;

export class GameClient {
  private socket: WebSocket | null = null;
  private listeners = new Set<() => void>();
  private sequence = 0;
  private watchdog: ReturnType<typeof setInterval> | null = null;
  private lastMessageAt = 0;
  private snapshot: Snapshot = {
    status: "disconnected",
    welcome: null,
    player: null,
    tick: 0,
    ack: 0,
    error: null,
  };

  constructor(
    private readonly url: string,
    private readonly makeSocket: SocketFactory = (url) => new WebSocket(url),
  ) {}

  getSnapshot = (): Snapshot => this.snapshot;
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  private publish(next: Partial<Snapshot>) {
    this.snapshot = { ...this.snapshot, ...next };
    for (const listener of this.listeners) listener();
  }

  connect() {
    this.disconnect();
    this.sequence = 0;
    this.publish({ status: "connecting", welcome: null, player: null, tick: 0, ack: 0, error: null });
    let socket: WebSocket;
    try {
      const target = new URL(this.url);
      if (
        !["ws:", "wss:"].includes(target.protocol) ||
        target.username ||
        target.password ||
        target.search ||
        target.hash
      )
        throw new Error("Invalid endpoint");
      socket = this.makeSocket(target.toString());
    } catch {
      this.publish({
        status: "error",
        error: "Địa chỉ WebSocket không hợp lệ hoặc trình duyệt đã từ chối kết nối.",
      });
      return;
    }
    this.socket = socket;
    this.lastMessageAt = Date.now();
    this.watchdog = setInterval(() => {
      if (this.socket === socket && Date.now() - this.lastMessageAt > 5000)
        this.fail("Backend không phản hồi. Hãy kết nối lại.");
    }, 1000);
    socket.onmessage = (event) => {
      if (this.socket !== socket) return;
      this.lastMessageAt = Date.now();
      try {
        if (typeof event.data !== "string") throw new Error("Text required");
        const message = serverMessage.parse(JSON.parse(event.data));
        if (message.type === "welcome") {
          if (this.snapshot.welcome) throw new Error("Duplicate welcome");
          if (message.player.x > message.world.width || message.player.y > message.world.height)
            throw new Error("Outside world");
          this.publish({ status: "connected", welcome: message, player: message.player });
        } else if (message.type === "state") {
          const world = this.snapshot.welcome?.world;
          if (
            !world ||
            message.player.x > world.width ||
            message.player.y > world.height ||
            message.ack > this.sequence ||
            message.tick <= this.snapshot.tick
          )
            throw new Error("Invalid state");
          this.publish({ player: message.player, tick: message.tick, ack: message.ack });
        } else if (message.type === "error") {
          this.fail("Backend từ chối message. Hãy kết nối lại.");
        } else if (!this.snapshot.welcome) throw new Error("Welcome required");
      } catch {
        this.fail("Phản hồi backend không đúng protocol v1.");
      }
    };
    socket.onerror = () => {
      if (this.socket === socket) this.fail("Không kết nối được backend. Kiểm tra terminal FastAPI.");
    };
    socket.onclose = () => {
      if (this.socket !== socket) return;
      this.disconnect();
      this.publish({ status: "disconnected", error: "Kết nối đã đóng. Bạn có thể kết nối lại." });
    };
  }

  sendInput(direction: Direction) {
    if (this.snapshot.status !== "connected" || this.socket?.readyState !== 1) return;
    if (this.sequence >= 2_147_483_647) {
      this.fail("Phiên thử nghiệm cần kết nối lại.");
      return;
    }
    const message = clientMessage.parse({ type: "input", seq: ++this.sequence, direction });
    try {
      this.socket.send(JSON.stringify(message));
    } catch {
      this.fail("Không gửi được input tới backend.");
    }
  }

  private fail(error: string) {
    this.disconnect();
    this.publish({ status: "error", error });
  }

  disconnect() {
    if (this.watchdog !== null) clearInterval(this.watchdog);
    this.watchdog = null;
    const socket = this.socket;
    this.socket = null;
    if (socket) {
      socket.onopen = socket.onmessage = socket.onerror = socket.onclose = null;
      socket.close();
    }
    this.publish({ status: "disconnected", welcome: null, player: null, tick: 0, ack: 0 });
  }
}
