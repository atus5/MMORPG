import Phaser from "phaser";
import { FoundationScene } from "./FoundationScene";
import type { GameClient } from "../network/GameClient";

export function createGame(parent: HTMLDivElement, client: GameClient) {
  return new Phaser.Game({
    type: Phaser.AUTO,
    parent,
    width: 960,
    height: 600,
    backgroundColor: "#102c2e",
    scene: [new FoundationScene(client, parent)],
    scale: { mode: Phaser.Scale.FIT, autoCenter: Phaser.Scale.CENTER_BOTH },
    input: { keyboard: { target: parent } },
    audio: { noAudio: true },
    render: { antialias: true },
  });
}
