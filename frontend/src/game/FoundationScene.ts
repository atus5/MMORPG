import Phaser from "phaser";
import type { GameClient } from "../network/GameClient";
import type { Direction } from "../network/protocol";

export class FoundationScene extends Phaser.Scene {
  private player!: Phaser.GameObjects.Container;
  private keys!: Record<string, Phaser.Input.Keyboard.Key>;
  private lastSent = 0;
  private lastDirection: Direction = "idle";
  private unsubscribe?: () => void;
  private worldReady = false;

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
      this.client.sendInput("idle");
      this.lastDirection = "idle";
    };
    const focus = () => this.host.focus({ preventScroll: true });
    const hidden = () => {
      if (document.hidden) stop();
    };
    this.host.addEventListener("pointerdown", focus);
    this.host.addEventListener("blur", stop);
    window.addEventListener("blur", stop);
    document.addEventListener("visibilitychange", hidden);
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, () => {
      this.unsubscribe?.();
      this.host.removeEventListener("pointerdown", focus);
      this.host.removeEventListener("blur", stop);
      window.removeEventListener("blur", stop);
      document.removeEventListener("visibilitychange", hidden);
      this.client.sendInput("idle");
    });
    this.renderState();
  }

  private renderState() {
    const snapshot = this.client.getSnapshot();
    if (snapshot.welcome && !this.worldReady) {
      this.worldReady = true;
      const { width, height } = snapshot.welcome.world;
      this.cameras.main.setBounds(0, 0, width, height);
      const g = this.add.graphics().setDepth(-10);
      g.fillStyle(0x193c38).fillRect(0, 0, width, height);
      g.lineStyle(1, 0x6aa286, 0.13);
      for (let x = 0; x <= width; x += 80) g.lineBetween(x, 0, x, height);
      for (let y = 0; y <= height; y += 80) g.lineBetween(0, y, width, y);
      g.fillStyle(0x1b5557).fillEllipse(width * 0.25, height * 0.55, 350, 720);
      g.lineStyle(3, 0x78a99c, 0.3).strokeEllipse(width * 0.25, height * 0.55, 350, 720);
      g.fillStyle(0x284c3c).fillEllipse(width * 0.7, height * 0.4, 600, 450);
      g.lineStyle(4, 0xd8cb9d, 0.4).strokeCircle(width / 2, height / 2, 100);
      g.lineStyle(1, 0xd8cb9d, 0.24).strokeCircle(width / 2, height / 2, 115);
      for (let n = 0; n < 36; n++) {
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
    this.player.setAlpha(snapshot.status === "connected" ? 1 : 0.4);
  }

  update(time: number) {
    if (
      this.client.getSnapshot().status !== "connected" ||
      document.activeElement !== this.host ||
      document.hidden
    )
      return;
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
