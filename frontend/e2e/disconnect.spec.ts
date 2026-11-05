import { expect, test } from "@playwright/test";

test("repeated page reloads receive fresh real-server sessions", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const opened = new Set<string>();
  page.on("websocket", (socket) => {
    if (socket.url() !== "ws://127.0.0.1:8000/ws") return;
    socket.on("framereceived", ({ payload }) => {
      const message = JSON.parse(String(payload));
      if (message.type === "welcome") {
        opened.add(message.connection_id);
      }
    });
  });
  await page.goto("/");
  let previousSessionCount = 0;
  for (let count = 1; count <= 4; count++) {
    await expect(page.getByTestId("connection-status")).toHaveAttribute("data-state", "connected");
    await expect(page.getByTestId("position")).toHaveText("X 800.0 · Y 500.0");
    await expect(page.locator("canvas")).toHaveCount(1);
    await expect.poll(() => opened.size).toBeGreaterThan(previousSessionCount);
    previousSessionCount = opened.size;
    if (count < 4) {
      await page.reload();
    }
  }
  await page.goto("about:blank");
  // Navigation tears down the old page's instrumentation; a Playwright "close" event
  // is not guaranteed for that destroyed context. Backend tests assert manager cleanup;
  // this real-server test verifies fresh sessions across reload and no browser exceptions.
  expect(errors).toEqual([]);
});
