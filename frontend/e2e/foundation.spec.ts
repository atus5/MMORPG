import { expect, test } from "@playwright/test";

test("real Next.js → WebSocket → authoritative FastAPI movement", async ({ page, request }) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const health = await request.get("http://127.0.0.1:8000/health");
  expect(health.status()).toBe(200);
  expect(await health.json()).toMatchObject({ status: "ok", protocol: 1 });
  await page.goto("/");
  await expect(page.getByTestId("connection-status")).toHaveAttribute("data-state", "connected");
  await expect(page.locator("canvas")).toHaveCount(1);
  await expect(page.getByTestId("position")).toHaveText("X 800.0 · Y 500.0");
  await page.getByTestId("game-viewport").click();
  await page.keyboard.down("d");
  await expect
    .poll(async () => Number((await page.getByTestId("position").textContent())?.match(/X ([\d.]+)/)?.[1]))
    .toBeGreaterThan(820);
  await page.keyboard.up("d");
  // A later server tick must settle; this is a real server assertion, not a mocked position.
  await page.waitForTimeout(200);
  const stopped = await page.getByTestId("position").textContent();
  await page.waitForTimeout(350);
  expect(await page.getByTestId("position").textContent()).toBe(stopped);
  await page.screenshot({ path: "test-results/m1-foundation.png", fullPage: true });
  await page.reload();
  await expect(page.getByTestId("connection-status")).toHaveAttribute("data-state", "connected");
  await expect(page.getByTestId("position")).toHaveText("X 800.0 · Y 500.0");
  await expect(page.locator("canvas")).toHaveCount(1);
  expect(errors).toEqual([]);
});

test("real server rejects client position injection and UI remains responsive on narrow viewport", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  await expect(page.getByTestId("connection-status")).toHaveAttribute("data-state", "connected");
  const reply = await page.evaluate(
    () =>
      new Promise<unknown>((resolve, reject) => {
        const socket = new WebSocket("ws://127.0.0.1:8000/ws");
        const timeout = setTimeout(() => {
          socket.close();
          reject(new Error("Validation timeout"));
        }, 3000);
        socket.onmessage = (event) => {
          const message = JSON.parse(event.data);
          if (message.type === "welcome")
            socket.send(JSON.stringify({ type: "input", seq: 1, direction: "right", x: 99999 }));
          if (message.type === "error") {
            clearTimeout(timeout);
            socket.close();
            resolve(message);
          }
        };
        socket.onerror = () => {
          clearTimeout(timeout);
          socket.close();
          reject(new Error("Socket failed"));
        };
      }),
  );
  expect(reply).toEqual({ type: "error", code: "invalid_message" });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await expect(page.locator("canvas")).toHaveCount(1);
});
