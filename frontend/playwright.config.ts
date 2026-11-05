import { defineConfig, devices } from "@playwright/test";

const python =
  process.platform === "win32" ? "../backend/.venv/Scripts/python.exe" : "../backend/.venv/bin/python";
export default defineConfig({
  testDir: "./e2e",
  fullyParallel: false,
  workers: 1,
  timeout: 30_000,
  reporter: "list",
  use: { baseURL: "http://127.0.0.1:3000", trace: "retain-on-failure" },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: [
    {
      command: `"${python}" -m uvicorn app.main:app --app-dir ../backend --host 127.0.0.1 --port 8000 --workers 1 --ws-max-size 4096 --ws-max-queue 64`,
      env: { TU_APP_ENV: "local", TU_M2_VERTICAL_SLICE: "1" },
      url: "http://127.0.0.1:8000/health",
      reuseExistingServer: false,
      timeout: 30_000,
    },
    {
      command: process.env.M1_E2E_DEV === "1" ? "npm run dev" : "npm run start",
      url: "http://127.0.0.1:3000",
      reuseExistingServer: false,
      timeout: 60_000,
    },
  ],
});
