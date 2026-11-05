import { expect, test } from "@playwright/test";

test("two independent local fixtures share movement, expiry and reconnect without duplicate entities", async ({
  browser,
  request,
}) => {
  const first = await browser.newContext();
  const second = await browser.newContext();
  const a = await first.newPage();
  const b = await second.newPage();
  const errors: string[] = [];
  a.on("pageerror", (error) => errors.push(error.message));
  b.on("pageerror", (error) => errors.push(error.message));
  let dropRenewals = false;
  let disconnect: (() => Promise<void>) | undefined;
  await a.routeWebSocket("ws://127.0.0.1:8000/m2/ws", (route) => {
    const server = route.connectToServer();
    route.onMessage((raw) => {
      const message = JSON.parse(String(raw));
      if (dropRenewals && message.type === "input" && message.direction !== "idle") return;
      server.send(raw);
    });
    disconnect = async () => {
      await server.close({ code: 1001, reason: "Injected local disconnect" });
      await route.close({ code: 1001, reason: "Injected local disconnect" });
    };
  });
  try {
    await a.goto("/vertical-slice");
    await expect(a.getByTestId("connection-status")).toHaveAttribute("data-state", "connected");
    await b.goto("/vertical-slice");
    await expect(b.getByTestId("connection-status")).toHaveAttribute("data-state", "connected");
    await expect(a.getByTestId("players").locator("li")).toHaveCount(2);
    await expect(b.getByTestId("players").locator("li")).toHaveCount(2);
    await expect(a.locator("canvas")).toHaveCount(1);
    await expect(b.locator("canvas")).toHaveCount(1);
    const ownA = a.locator('[data-testid="players"] [data-self="true"]');
    const ownB = b.locator('[data-testid="players"] [data-self="true"]');
    const idA = await ownA.getAttribute("data-entity-id");
    const idB = await ownB.getAttribute("data-entity-id");
    expect(idA).not.toBe(idB);
    expect(await ownA.getAttribute("data-x")).toBe("760");
    expect(await ownB.getAttribute("data-x")).toBe("840");
    const peerAInB = b.locator(`[data-entity-id="${idA}"]`);
    const peerBInA = a.locator(`[data-entity-id="${idB}"]`);
    await a.getByTestId("game-viewport").click();
    await a.keyboard.down("d");
    await expect.poll(async () => Number(await peerAInB.getAttribute("data-x"))).toBeGreaterThan(762);
    await a.keyboard.up("d");
    await b.getByTestId("game-viewport").click();
    await b.keyboard.down("a");
    await expect.poll(async () => Number(await peerBInA.getAttribute("data-x"))).toBeLessThan(838);
    await b.keyboard.up("a");
    await a.getByTestId("game-viewport").click();
    const beforeExpiry = Number(await ownA.getAttribute("data-x"));
    await a.keyboard.down("d");
    await expect
      .poll(async () => Number(await peerAInB.getAttribute("data-x")))
      .toBeGreaterThan(beforeExpiry + 2);
    dropRenewals = true; // Drop network renewals while the physical key remains down.
    await expect(a.getByTestId("input-state")).toContainText("Thả phím");
    await a.waitForTimeout(100);
    const expired = await ownA.getAttribute("data-x");
    dropRenewals = false;
    await a.waitForTimeout(350);
    expect(await ownA.getAttribute("data-x")).toBe(expired);
    await a.keyboard.up("d");
    await a.keyboard.down("d");
    await expect
      .poll(async () => Number(await peerAInB.getAttribute("data-x")))
      .toBeGreaterThan(Number(expired) + 2);
    await a.keyboard.up("d");
    await a.waitForTimeout(100);
    const stored = await ownA.getAttribute("data-x");
    const canvas = await a.locator("canvas").elementHandle();
    if (!disconnect || !canvas) throw new Error("Local multiplayer connection did not initialize");
    await disconnect();
    await expect(a.getByTestId("connection-status")).toHaveAttribute("data-state", "disconnected");
    await expect(a.getByTestId("players").locator("li")).toHaveCount(0);
    await expect(b.getByTestId("players").locator("li")).toHaveCount(1);
    await a.getByRole("button", { name: "Kết nối lại" }).click();
    await expect(a.getByTestId("connection-status")).toHaveAttribute("data-state", "connected");
    await expect(a.getByTestId("players").locator("li")).toHaveCount(2);
    expect(await ownA.getAttribute("data-entity-id")).toBe(idA);
    expect(await ownA.getAttribute("data-x")).toBe(stored);
    expect(await canvas.evaluate((node) => node === document.querySelector("canvas"))).toBe(true);
    await expect(b.getByTestId("players").locator("li")).toHaveCount(2);
    await a.screenshot({ path: "test-results/m2-vertical-slice-a.png", fullPage: true });
    await b.screenshot({ path: "test-results/m2-vertical-slice-b.png", fullPage: true });
    const metrics = await a.request.get("http://127.0.0.1:8000/m2/metrics", {
      headers: { origin: "http://127.0.0.1:3000" },
    });
    expect(metrics.status()).toBe(200);
    const observations = await metrics.json();
    expect(observations.active_players).toBe(2);
    console.log("M2 local metrics", JSON.stringify(observations));
    await test.info().attach("m2-local-metrics", {
      body: JSON.stringify(observations, null, 2),
      contentType: "application/json",
    });
    expect(errors).toEqual([]);
  } catch (error) {
    const diagnostics = {
      a: await a.getByTestId("connection-status").getAttribute("data-state"),
      b: await b.getByTestId("connection-status").getAttribute("data-state"),
      alerts: await a.getByRole("alert").allTextContents(),
      errors,
    };
    console.log("M2 browser failure", JSON.stringify(diagnostics));
    await test.info().attach("m2-browser-failure", {
      body: JSON.stringify(diagnostics),
      contentType: "application/json",
    });
    throw error;
  } finally {
    await first.close();
    await second.close();
  }
  await expect
    .poll(async () => {
      const response = await request.get("http://127.0.0.1:8000/m2/metrics", {
        headers: { origin: "http://127.0.0.1:3000" },
      });
      return (await response.json()).active_players;
    })
    .toBe(0);
});
