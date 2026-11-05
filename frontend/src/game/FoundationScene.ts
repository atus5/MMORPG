import Phaser from "phaser";
import type { GameClient } from "../network/GameClient";
import type { Direction } from "../network/protocol";

export class FoundationScene extends Phaser.Scene {
  private player!: Phaser.GameObjects.Container;
  private playerRing?: Phaser.GameObjects.Graphics;
  private keys!: Record<string, Phaser.Input.Keyboard.Key>;
  private lastSent = 0;
  private lastDirection: Direction = "idle";
  private unsubscribe?: () => void;
  private worldReady = false;
  private peers = new Map<string, Phaser.GameObjects.Container>();
  private pressedCodes = new Set<string>();
  private blockedUntilRelease = false;
  private lastReleaseRequired = false;
  private lastGeneration = 0;

  constructor(
    private readonly client: GameClient,
    private readonly host: HTMLDivElement,
  ) {
    super("foundation");
  }

  create() {
    const keyboard = this.input.keyboard;
    if (!keyboard) throw new Error("The foundation scene requires keyboard input");
    this.keys = keyboard.addKeys("W,A,S,D,UP,DOWN,LEFT,RIGHT") as Record<string, Phaser.Input.Keyboard.Key>;
    const shadow = this.add.ellipse(0, 17, 33, 12, 0x03151b, 0.5);
    const robe = this.add.triangle(0, 3, -15, 18, 0, -15, 15, 18, 0xe5d6a4);
    const sash = this.add.rectangle(0, 8, 20, 4, 0x53c1a2);
    const head = this.add.circle(0, -15, 8, 0xf4dfbd);
    const hair = this.add.ellipse(0, -21, 15, 9, 0x16383d);
    this.player = this.add.container(0, 0, [shadow, robe, sash, head, hair]).setDepth(20).setVisible(false);
    this.cameras.main.startFollow(this.player, true, 0.15, 0.15);
    this.unsubscribe = this.client.subscribe(() => this.renderState());
    const stop = () => {
      this.input.keyboard?.resetKeys();
      this.pressedCodes.clear();
      this.blockedUntilRelease = false;
      this.client.sendInput("idle");
      this.lastDirection = "idle";
    };
    const focus = () => this.host.focus({ preventScroll: true });
    const hidden = () => {
      if (document.hidden) stop();
    };
    this.host.addEventListener("pointerdown", focus);
    const keydown = (event: KeyboardEvent) => this.sliceKey(event, true);
    const keyup = (event: KeyboardEvent) => this.sliceKey(event, false);
    this.host.addEventListener("keydown", keydown);
    this.host.addEventListener("keyup", keyup);
    this.host.addEventListener("blur", stop);
    window.addEventListener("blur", stop);
    document.addEventListener("visibilitychange", hidden);
    let cleaned = false;
    const cleanup = () => {
      if (cleaned) return;
      cleaned = true;
      this.unsubscribe?.();
      this.unsubscribe = undefined;
      this.host.removeEventListener("pointerdown", focus);
      this.host.removeEventListener("keydown", keydown);
      this.host.removeEventListener("keyup", keyup);
      for (const peer of this.peers.values()) peer.destroy();
      this.peers.clear();
      this.host.removeEventListener("blur", stop);
      window.removeEventListener("blur", stop);
      document.removeEventListener("visibilitychange", hidden);
      this.client.sendInput("idle");
    };
    // Game.destroy (including React Strict Mode cleanup) emits DESTROY without SHUTDOWN.
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, cleanup);
    this.events.once(Phaser.Scenes.Events.DESTROY, cleanup);
    this.renderState();
  }

  private renderState() {
    const snapshot = this.client.getSnapshot();
    if (snapshot.status !== "connected") {
      this.lastDirection = "idle";
      this.pressedCodes.clear();
      this.blockedUntilRelease = false;
      this.lastReleaseRequired = false;
      this.lastGeneration = 0;
    } else if (snapshot.verticalSlice) {
      if (
        snapshot.releaseRequired &&
        (!this.lastReleaseRequired || snapshot.generation !== this.lastGeneration)
      )
        this.blockedUntilRelease = true;
      this.lastReleaseRequired = !!snapshot.releaseRequired;
      this.lastGeneration = snapshot.generation ?? 0;
    }
    if (snapshot.welcome && !this.worldReady) {
      this.worldReady = true;
      const { width, height } = snapshot.welcome.world;
      this.cameras.main.setBounds(0, 0, width, height);
      const g = this.add.graphics().setDepth(-10);
      g.fillStyle(0x193c38).fillRect(0, 0, width, height);
      g.lineStyle(1, 0x6aa286, 0.13);
      for (let x = 0; x <= width; x += 80) g.lineBetween(x, 0, x, height);
      for (let y = 0; y <= height; y += 80) g.lineBetween(0, y, width, y);
      if (!snapshot.verticalSlice) {
        g.fillStyle(0x1b5557).fillEllipse(width * 0.25, height * 0.55, 350, 720);
        g.lineStyle(3, 0x78a99c, 0.3).strokeEllipse(width * 0.25, height * 0.55, 350, 720);
        g.fillStyle(0x284c3c).fillEllipse(width * 0.7, height * 0.4, 600, 450);
      }
      // Keep the existing ring geometry, but own its visibility separately from the world.
      this.playerRing = this.add.graphics().setDepth(-10);
      this.playerRing.lineStyle(4, 0xd8cb9d, 0.4).strokeCircle(width / 2, height / 2, 100);
      this.playerRing.lineStyle(1, 0xd8cb9d, 0.24).strokeCircle(width / 2, height / 2, 115);
      for (let n = 0; n < (snapshot.verticalSlice ? 0 : 36); n++) {
        const x = 100 + ((n * 239) % (width - 200));
        const y = 70 + ((n * 173) % (height - 140));
        if (Math.abs(x - width / 2) < 150 && Math.abs(y - height / 2) < 150) continue;
        g.fillStyle(0x0e2c29, 0.4).fillEllipse(x + 6, y + 25, 52, 18);
        g.fillStyle(0x547564).fillCircle(x, y, 20);
        g.fillStyle(0x6b8d70).fillCircle(x - 7, y - 10, 16);
      }
      this.add
        .text(width / 2, height / 2 + 140, "ĐÀI THỬ LUYỆN", {
          fontFamily: "Georgia",
          fontSize: "14px",
          color: "#b8cbb5",
          letterSpacing: 4,
        })
        .setOrigin(0.5);
    }
    // Position is rendered only from validated server messages. No client movement integration.
    if (snapshot.player) this.player.setPosition(snapshot.player.x, snapshot.player.y).setVisible(true);
    else this.player.setVisible(false);
    this.playerRing?.setVisible(snapshot.player !== null);
    this.player.setAlpha(snapshot.status === "connected" ? 1 : 0.4);
    this.renderPeers();
  }

  private renderPeers() {
    const snapshot = this.client.getSnapshot();
    const players =
      snapshot.verticalSlice && snapshot.status === "connected"
        ? (snapshot.players ?? []).filter((player) => player.id !== snapshot.selfId)
        : [];
    const ids = new Set(players.map((player) => player.id));
    for (const [id, peer] of this.peers) {
      if (!ids.has(id)) {
        peer.destroy();
        this.peers.delete(id);
      }
    }
    for (const player of players) {
      let peer = this.peers.get(player.id);
      if (!peer) {
        peer = this.add
          .container(0, 0, [
            this.add.ellipse(0, 17, 33, 12, 0x03151b, 0.5),
            this.add.triangle(0, 3, -15, 18, 0, -15, 15, 18, 0xa7d6e5),
            this.add.rectangle(0, 8, 20, 4, 0x579fce),
            this.add.circle(0, -15, 8, 0xf4dfbd),
            this.add.ellipse(0, -21, 15, 9, 0x16383d),
          ])
          .setDepth(19);
        this.peers.set(player.id, peer);
      }
      peer.setPosition(player.x, player.y);
    }
  }

  private sliceDirection(): Direction {
    if (this.pressedCodes.has("KeyW") || this.pressedCodes.has("ArrowUp")) return "up";
    if (this.pressedCodes.has("KeyS") || this.pressedCodes.has("ArrowDown")) return "down";
    if (this.pressedCodes.has("KeyA") || this.pressedCodes.has("ArrowLeft")) return "left";
    if (this.pressedCodes.has("KeyD") || this.pressedCodes.has("ArrowRight")) return "right";
    return "idle";
  }

  private sliceKey(event: KeyboardEvent, down: boolean) {
    const snapshot = this.client.getSnapshot();
    if (
      !snapshot.verticalSlice ||
      !["KeyW", "KeyA", "KeyS", "KeyD", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(
        event.code,
      )
    )
      return;
    event.preventDefault();
    if (down && (event.repeat || document.activeElement !== this.host || document.hidden)) return;
    if (down) this.pressedCodes.add(event.code);
    else this.pressedCodes.delete(event.code);
    if (snapshot.status !== "connected") return;
    const direction = this.sliceDirection();
    if (this.blockedUntilRelease) {
      if (this.pressedCodes.size !== 0) return;
      this.blockedUntilRelease = false;
      this.client.sendInput("idle");
      this.lastDirection = "idle";
      return;
    }
    if (direction !== this.lastDirection) {
      this.client.sendInput(direction);
      this.lastDirection = direction;
      this.lastSent = this.time?.now ?? 0;
    }
  }

  update(time: number) {
    if (
      this.client.getSnapshot().status !== "connected" ||
      document.activeElement !== this.host ||
      document.hidden
    )
      return;
    if (this.client.getSnapshot().verticalSlice) {
      // Edges are sent by DOM callbacks between frames; update only renews an unexpired hold.
      const direction = this.sliceDirection();
      if (!this.blockedUntilRelease && direction !== "idle" && time - this.lastSent >= 100) {
        this.client.sendInput(direction);
        this.lastSent = time;
      }
      return;
    }
    const keys = this.keys;
    let direction: Direction = "idle";
    if (keys.W.isDown || keys.UP.isDown) direction = "up";
    else if (keys.S.isDown || keys.DOWN.isDown) direction = "down";
    else if (keys.A.isDown || keys.LEFT.isDown) direction = "left";
    else if (keys.D.isDown || keys.RIGHT.isDown) direction = "right";
    if (direction !== this.lastDirection || (direction !== "idle" && time - this.lastSent >= 100)) {
      this.client.sendInput(direction);
      this.lastDirection = direction;
      this.lastSent = time;
    }
  }
}
