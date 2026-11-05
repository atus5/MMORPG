import {
  clientMessage,
  serverMessage,
  sliceClientMessage,
  sliceServerMessage,
  type Direction,
  type PublicPlayer,
  type SliceWelcome,
  type Welcome,
} from "./protocol";

export type ConnectionStatus = "disconnected" | "connecting" | "connected" | "error";
export type Snapshot = {
  status: ConnectionStatus;
  welcome: Welcome | SliceWelcome | null;
  player: { x: number; y: number } | null;
  tick: number;
  ack: number;
  error: string | null;
  verticalSlice?: boolean;
  players?: PublicPlayer[];
  selfId?: string | null;
  bootId?: string | null;
  generation?: number;
  streamSeq?: number;
  releaseRequired?: boolean;
};
type SocketFactory = (url: string) => WebSocket;
type ClientOptions = {
  verticalSlice?: boolean;
  bootstrap?: (url: string) => Promise<void>;
};

export class GameClient {
  private socket: WebSocket | null = null;
  private listeners = new Set<() => void>();
  private sequence = 0;
  private watchdog: ReturnType<typeof setInterval> | null = null;
  private lastMessageAt = 0;
  private attempt = 0;
  private bootstrapPromise: Promise<void> | null = null;
  private bootstrapTimer: ReturnType<typeof setTimeout> | null = null;
  private inputBlocked = false;
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
    private readonly options: ClientOptions = {},
  ) {
    this.snapshot.verticalSlice = options.verticalSlice ?? false;
  }

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
    const attempt = this.attempt;
    if (this.options.verticalSlice) {
      this.bootstrapTimer = setTimeout(() => {
        if (attempt === this.attempt) this.fail("Backend không phản hồi. Hãy kết nối lại.");
      }, 5000);
      void this.bootstrap().then(
        () => {
          if (attempt !== this.attempt) return;
          if (this.bootstrapTimer !== null) clearTimeout(this.bootstrapTimer);
          this.bootstrapTimer = null;
          this.openSocket();
        },
        () => {
          if (attempt === this.attempt) this.fail("Không cấp được fixture local. Kiểm tra backend.");
        },
      );
    } else this.openSocket();
  }

  private target() {
    const target = new URL(this.url);
    if (
      !["ws:", "wss:"].includes(target.protocol) ||
      target.username ||
      target.password ||
      target.search ||
      target.hash
    )
      throw new Error("Invalid endpoint");
    if (this.options.verticalSlice) target.pathname = "/m2/ws";
    return target;
  }

  private async bootstrap() {
    if (this.bootstrapPromise === null) {
      const target = this.target();
      target.protocol = target.protocol === "ws:" ? "http:" : "https:";
      target.pathname = "/m2/session";
      this.bootstrapPromise = this.options.bootstrap
        ? this.options.bootstrap(target.toString())
        : fetch(target, { method: "POST", credentials: "include", cache: "no-store" }).then((response) => {
            if (!response.ok) throw new Error("Fixture unavailable");
          });
      // Keep one pending bootstrap across Strict Mode setup/cleanup. No identity is chosen by the client.
      const pending = this.bootstrapPromise;
      void pending.then(
        () => {
          if (this.bootstrapPromise === pending) this.bootstrapPromise = null;
        },
        () => {
          if (this.bootstrapPromise === pending) this.bootstrapPromise = null;
        },
      );
    }
    await this.bootstrapPromise;
  }

  private openSocket() {
    let socket: WebSocket;
    try {
      const target = this.target();
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
        if (this.options.verticalSlice) {
          this.receiveSlice(JSON.parse(event.data));
          return;
        }
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
        this.fail("Phản hồi backend không đúng protocol.");
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

  private receiveSlice(raw: unknown) {
    const message = sliceServerMessage.parse(raw);
    if (message.type === "error") {
      this.fail("Backend từ chối message. Hãy kết nối lại.");
      return;
    }
    if (message.type === "pong") {
      if (!this.snapshot.welcome) throw new Error("Welcome required");
      return;
    }
    const welcome = message.type === "welcome" ? message : this.snapshot.welcome;
    if (welcome?.protocol !== 2) throw new Error("Version 2 welcome required");
    if (message.type === "welcome" && this.snapshot.welcome) throw new Error("Duplicate welcome");
    const own = message.players.find((player) => player.id === message.self_id);
    if (
      !own ||
      own.x !== message.player.x ||
      own.y !== message.player.y ||
      new Set(message.players.map((player) => player.id)).size !== message.players.length ||
      message.players.some((player) => player.x > welcome.world.width || player.y > welcome.world.height) ||
      message.ack_received > this.sequence ||
      message.ack_applied > message.ack_received
    )
      throw new Error("Invalid authoritative baseline");
    if (
      message.type !== "welcome" &&
      (message.boot_id !== this.snapshot.bootId ||
        message.self_id !== this.snapshot.selfId ||
        message.stream_seq <= (this.snapshot.streamSeq ?? 0) ||
        message.tick < this.snapshot.tick ||
        message.generation < (this.snapshot.generation ?? 0) ||
        (message.type !== "resync" && message.generation !== this.snapshot.generation))
    )
      throw new Error("Stale baseline or generation");
    if (
      message.release_required &&
      (!this.snapshot.releaseRequired || message.generation !== this.snapshot.generation)
    )
      this.inputBlocked = true;
    if (!message.release_required) this.inputBlocked = false;
    this.publish({
      status: "connected",
      welcome,
      player: message.player,
      players: message.players,
      selfId: message.self_id,
      bootId: message.boot_id,
      generation: message.generation,
      streamSeq: message.stream_seq,
      releaseRequired: message.release_required,
      tick: message.tick,
      ack: message.ack_applied,
      error: message.type === "resync" ? "Server đã đồng bộ lại. Thả phím rồi nhấn lại." : null,
    });
  }

  sendInput(direction: Direction) {
    if (this.snapshot.status !== "connected" || this.socket?.readyState !== 1) return;
    if (this.options.verticalSlice && this.inputBlocked && direction !== "idle") return;
    if (this.sequence >= 2_147_483_647) {
      this.fail("Phiên thử nghiệm cần kết nối lại.");
      return;
    }
    const message = this.options.verticalSlice
      ? sliceClientMessage.parse({
          type: "input",
          seq: ++this.sequence,
          direction,
          generation: this.snapshot.generation,
        })
      : clientMessage.parse({ type: "input", seq: ++this.sequence, direction });
    if (direction === "idle") this.inputBlocked = false;
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
    this.attempt++;
    if (this.bootstrapTimer !== null) clearTimeout(this.bootstrapTimer);
    this.bootstrapTimer = null;
    if (this.watchdog !== null) clearInterval(this.watchdog);
    this.watchdog = null;
    const socket = this.socket;
    this.socket = null;
    if (socket) {
      socket.onopen = socket.onmessage = socket.onerror = socket.onclose = null;
      socket.close();
    }
    this.inputBlocked = false;
    this.publish({
      status: "disconnected",
      welcome: null,
      player: null,
      tick: 0,
      ack: 0,
      players: [],
      selfId: null,
      bootId: null,
      generation: 0,
      streamSeq: 0,
      releaseRequired: false,
    });
  }
}
