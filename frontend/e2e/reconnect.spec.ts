import { expect, test } from "@playwright/test";

test("failed reconnect clears old session while retaining the original canvas", async ({ page }) => {
  let refuseReconnect = false;
  let disconnect: (() => Promise<void>) | undefined;
  await page.routeWebSocket("ws://127.0.0.1:8000/ws", (route) => {
    if (refuseReconnect) {
      void route.close({ code: 1013, reason: "Injected reconnect failure" });
      return;
    }
    // Initial connection and later recovery use the actual FastAPI backend.
    route.connectToServer();
    disconnect = () => route.close({ code: 1001, reason: "Injected connection loss" });
  });
  await page.goto("/");
  await expect(page.getByTestId("connection-status")).toHaveAttribute("data-state", "connected");
  await expect(page.locator("canvas")).toHaveCount(1);
  const canvas = await page.locator("canvas").elementHandle();
  if (!canvas || !disconnect) throw new Error("Live game connection did not initialize");
  await page.getByTestId("game-viewport").click();
  await page.keyboard.down("d");
  await expect
    .poll(async () => await page.getByTestId("position").textContent())
    .not.toBe("X 800.0 · Y 500.0");
  refuseReconnect = true;
  await disconnect();
  await page.keyboard.up("d");
  await expect(page.getByTestId("connection-status")).toHaveAttribute("data-state", "disconnected");
  await expect(page.getByTestId("position")).toHaveText("Đang chờ state từ server");
  await page.getByRole("button", { name: "Kết nối lại" }).click();
  await expect(page.getByTestId("connection-status")).toHaveAttribute("data-state", "disconnected");
  await expect(page.getByTestId("position")).toHaveText("Đang chờ state từ server");
  expect(await canvas.evaluate((node) => node === document.querySelector("canvas"))).toBe(true);
  await expect(page.locator("canvas")).toHaveCount(1);
  refuseReconnect = false;
  await page.getByRole("button", { name: "Kết nối lại" }).click();
  await expect(page.getByTestId("connection-status")).toHaveAttribute("data-state", "connected");
  await expect(page.getByTestId("position")).toHaveText("X 800.0 · Y 500.0");
  expect(await canvas.evaluate((node) => node === document.querySelector("canvas"))).toBe(true);
});
