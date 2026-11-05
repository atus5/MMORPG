"use client";

import dynamic from "next/dynamic";
import Link from "next/link";
import { useEffect, useState, useSyncExternalStore } from "react";
import { GameClient } from "../network/GameClient";

const GameViewport = dynamic(() => import("./GameViewport"), {
  ssr: false,
  loading: () => <div className="canvas-loading">Đang mở đài thử luyện…</div>,
});
const labels = {
  disconnected: "Chưa kết nối",
  connecting: "Đang kết nối",
  connected: "Đã kết nối",
  error: "Lỗi kết nối",
};

export function GameShell({ mode = "foundation" }: { mode?: "foundation" | "vertical-slice" }) {
  const vertical = mode === "vertical-slice";
  const [client] = useState(
    () =>
      new GameClient(process.env.NEXT_PUBLIC_WS_URL ?? "ws://127.0.0.1:8000/ws", undefined, {
        verticalSlice: vertical,
      }),
  );
  const state = useSyncExternalStore(client.subscribe, client.getSnapshot, client.getSnapshot);
  useEffect(() => {
    client.connect();
    return () => client.disconnect();
  }, [client]);
  return (
    <main className="shell">
      <header className="masthead">
        <Link href="/" className="brand">
          <span className="seal">仙</span>
          <span>
            TU TIÊN <em>ONLINE</em>
          </span>
        </Link>
        <span className="milestone">{vertical ? "M2 · LOCAL VERTICAL SLICE" : "M1 · GAME FOUNDATION"}</span>
      </header>
      <section className="intro">
        <div>
          <p className="eyebrow">KHỞI ĐẦU MỘT HÀNH TRÌNH</p>
          <h1>Một bước vào tiên lộ.</h1>
          <p className="lede">
            Không gian thử nghiệm đầu tiên của Tu Tiên Online.
            <br />
            Di chuyển, khám phá và kiểm tra kết nối thời gian thực.
          </p>
        </div>
        <div className="chapter">
          <span>01</span>
          <p>
            ĐÀI THỬ LUYỆN
            <br />
            <small>Local development</small>
          </p>
        </div>
      </section>
      <section className="game-panel" aria-label="Không gian thử nghiệm">
        <div className="panel-bar">
          <span className="location">
            <i />
            {vertical ? "Thế giới thử nghiệm chung" : "Thanh Vân · Sandbox"}
          </span>
          <div className="connection">
            <span
              className={`status ${state.status}`}
              role="status"
              data-testid="connection-status"
              data-state={state.status}
            >
              {labels[state.status]}
            </span>
            <button
              type="button"
              onClick={() => client.connect()}
              disabled={state.status === "connecting" || state.status === "connected"}
            >
              Kết nối lại
            </button>
          </div>
        </div>
        <GameViewport client={client} />
        <div className="panel-footer">
          <span>
            <kbd>W</kbd>
            <kbd>A</kbd>
            <kbd>S</kbd>
            <kbd>D</kbd> hoặc phím mũi tên <span className="muted">· Nhấn vào canvas để di chuyển</span>
          </span>
          <output data-testid="position">
            {state.player
              ? `X ${state.player.x.toFixed(1)} · Y ${state.player.y.toFixed(1)}`
              : "Đang chờ state từ server"}
          </output>
        </div>
      </section>
      {vertical && (
        <section className="notes" aria-label="Người chơi trong thế giới local">
          <article>
            <h2>Hai phiên, cùng một thế giới.</h2>
            <p data-testid="input-state" role="status">
              {state.releaseRequired
                ? "Input đã hết hạn hoặc đồng bộ lại. Thả phím rồi nhấn lại."
                : state.status === "connected"
                  ? "Sẵn sàng di chuyển."
                  : "Đang chờ kết nối."}
            </p>
            <ul data-testid="players">
              {(state.players ?? []).map((player) => (
                <li
                  key={player.id}
                  data-entity-id={player.id}
                  data-self={player.id === state.selfId}
                  data-x={player.x}
                  data-y={player.y}
                >
                  {player.label}
                  {player.id === state.selfId ? " (bạn)" : ""}
                  {` · X ${player.x.toFixed(1)} · Y ${player.y.toFixed(1)}`}
                </li>
              ))}
            </ul>
          </article>
        </section>
      )}
      {state.error && (
        <p className="error-message" role="alert">
          {state.error}
        </p>
      )}
      <section className="notes" aria-label="Thông tin phiên thử nghiệm">
        <article>
          <span className="note-number">01 / INPUT</span>
          <h2>Gửi ý định. Nhận trạng thái.</h2>
          <p>Phím bấm được gửi tới backend. Nhân vật chỉ di chuyển khi server trả về vị trí đã xác thực.</p>
        </article>
        <article>
          <span className="note-number">02 / SESSION</span>
          <h2>{vertical ? "Danh tính test do server cấp." : "Mỗi kết nối, một phiên thử."}</h2>
          <p>
            {vertical
              ? "Kết nối lại giữ vị trí trong RAM. Restart backend tạo lại state; không có đăng nhập thật."
              : "Phiên tạm trong bộ nhớ. Kết nối lại sẽ bắt đầu mới; chưa có đăng nhập hay lưu tiến trình."}
          </p>
        </article>
        <article>
          <span className="note-number">03 / SCOPE</span>
          <h2>{vertical ? "Một thế giới local, không persistence." : "Nền móng trước, thế giới sau."}</h2>
          <p>Chưa có chiến đấu, cảnh giới, cơ duyên hay luật PvP. Các thông số ở đây chỉ dành cho sandbox.</p>
        </article>
      </section>
      <footer className="page-footer">
        <span>TU TIÊN ONLINE</span>
        <span>Next.js · Phaser 3 · FastAPI · WebSocket</span>
        <span>{vertical ? "LOCAL MULTIPLAYER / M2" : "PROTOTYPE / M1"}</span>
      </footer>
    </main>
  );
}
