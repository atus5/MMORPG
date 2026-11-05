"use client";

import { useEffect, useRef } from "react";
import { createGame } from "../game/createGame";
import type { GameClient } from "../network/GameClient";

export default function GameViewport({ client }: { client: GameClient }) {
  const parent = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!parent.current) return;
    const game = createGame(parent.current, client);
    return () => {
      game.destroy(true);
    };
  }, [client]);
  return (
    <div
      ref={parent}
      className="game-viewport"
      // biome-ignore lint/a11y/noNoninteractiveTabindex: Phaser requires a focusable surface for scoped keyboard controls.
      tabIndex={0}
      role="application"
      aria-label="Game thử nghiệm: nhấn để lấy focus, dùng WASD hoặc phím mũi tên"
      data-testid="game-viewport"
    />
  );
}
