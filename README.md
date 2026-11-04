# Tu Tiên Online — M1 Game Foundation

Bộ khung chạy **local**: Next.js + TypeScript → Phaser 3 → WebSocket → FastAPI. Chưa có Supabase/Auth/database, combat, tiến trình nhân vật hoặc thế giới nhiều người chơi. M1 đang chờ Gemini 4 Argon review độc lập; kết quả test của Codex không thay thế approval.

## Yêu cầu

- Windows PowerShell, Node.js **22.12+** (đã kiểm tra 22.19.0), npm 10+, Python **3.10+** (đã kiểm tra 3.10.11).
- Cổng local 3000/8000 còn trống. Không mở các server này ra Internet.
- Không cần Supabase CLI, key hoặc database. Cài npm/pip từ registry chính thức.

## Backend — terminal 1

```powershell
Set-Location 'F:\MMRPG PNTT\backend'
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --ws-max-size 4096
```

Không cần activate venv hoặc đổi ExecutionPolicy. `requirements.txt` khóa runtime; `requirements-dev.txt` khóa cả test tools; `.in` lưu dependency đầu vào. Các `.txt` là tập phiên bản đã resolve trên Windows.

Kiểm tra: `Invoke-RestMethod http://127.0.0.1:8000/health` trả `status: ok`, `protocol: 1`. WebSocket: `ws://127.0.0.1:8000/ws`. Origin mặc định chỉ cho phép `http://localhost:3000` và `http://127.0.0.1:3000`.

Muốn đổi origin, sao chép `backend/.env.example` thành `.env`, sửa giá trị public rồi thêm `--env-file .env` vào lệnh Uvicorn. CORS không thay thế authentication; backend này **chỉ dành cho local**, chưa phù hợp production. Chỉ dùng một process/worker; session trong bộ nhớ không chia sẻ giữa worker.

## Frontend — terminal 2

```powershell
Set-Location 'F:\MMRPG PNTT\frontend'
npm ci
npm run dev
```

Mở **http://127.0.0.1:3000**. Chờ “Đã kết nối”, nhấn vào canvas, dùng WASD hoặc phím mũi tên. Camera theo nhân vật. Mất focus/input hết hạn sẽ dừng di chuyển. Tắt backend để quan sát disconnect, chạy lại rồi chọn “Kết nối lại”. Kết nối mới tạo session mới ở giữa map.

Không bắt buộc tạo `.env`. Muốn đổi endpoint, sao chép `frontend/.env.example` thành `.env.local`. `NEXT_PUBLIC_WS_URL` là địa chỉ public nhúng khi build; restart dev server/build lại sau khi đổi. **Không đặt secret/service-role key trong `NEXT_PUBLIC_*`.** Trang HTTPS cần WSS; M1 mặc định dùng HTTP/WS trên loopback.

## Build/test

Tại `backend/`:

```powershell
.\.venv\Scripts\python.exe -m pip check
.\.venv\Scripts\python.exe -m ruff check .
.\.venv\Scripts\python.exe -m pytest
```

Tại `frontend/`:

```powershell
npm run typecheck
npm run lint
npm test
npm run build
npx playwright install chromium
npm run test:e2e
```

E2E yêu cầu backend venv đã cài và frontend đã build. Playwright tự khởi tạo server local tại 3000/8000, kiểm tra health/canvas/WebSocket/movement/stop/reload/validation rồi dừng process do nó tạo. Không chạy khi server của bạn đang chiếm hai cổng này (`reuseExistingServer: false`). Log/trace/screenshot nằm trong `frontend/test-results/`, được ignore. Không dùng test runner hoặc CLI AI trong `.automation/` để test M1.

Kiểm tra thêm dev/React Strict Mode: chạy `$env:M1_E2E_DEV='1'; npm run test:e2e` trong PowerShell riêng (đóng terminal đó sau khi test). Đây là tùy chọn chỉ cho E2E, không phải cấu hình game. Hiện test tự động dùng Chromium; trình duyệt khác và điều khiển cảm ứng chưa được xác minh.

Bản build chạy bằng `npm run start` trong `frontend/`, backend vẫn ở terminal riêng. Ctrl+C dừng từng server. Quy trình này không truy cập Supabase hoặc chạy migration.

## Cấu trúc

```text
frontend/src/app/          Next.js App Router + trang chính
frontend/src/components/  React UI + mount/unmount Phaser (SSR off)
frontend/src/game/        Phaser scene, camera, bàn phím; render state server
frontend/src/network/     Protocol validation + WebSocket lifecycle/store
frontend/e2e/             Browser test frontend/backend thật
backend/app/config.py     Transport limits + sandbox kỹ thuật
backend/app/protocol.py   Pydantic protocol v1
backend/app/connections.py Session tạm, server clock, authoritative position
backend/app/routes.py     /health, /ws, validation, disconnect
backend/app/main.py       App factory + CORS
backend/tests/            Protocol, transport, authority, cleanup tests
docs/                     Kế hoạch M1 + protocol
```

Xem [docs/PROTOCOL.md](docs/PROTOCOL.md). Phaser chỉ nạp trong browser bằng `next/dynamic` với `ssr: false` từ Client Component. React quản lý UI; transport quản lý socket; scene quản lý input/render, không tích phân vị trí client. Không tải font/asset từ CDN.

Map/pixel speed/tick/input lease chỉ là thông số sandbox tạm, chưa phải luật game. Mỗi connection có nhân vật riêng, chưa broadcast người chơi khác. Cơ duyên, thế giới/cảnh giới, HP/damage, PvP, hồi sinh, chết/thăng giới và lôi kiếp chưa được định nghĩa hoặc mặc định hóa.

## Review

Codex làm việc ở `tu`; không commit/push/merge/deploy khi chưa được Owner cho phép. Đọc [AGENTS.md](AGENTS.md), [DESKTOP_WORKFLOW.md](DESKTOP_WORKFLOW.md) và [GEMINI_REVIEW.md](GEMINI_REVIEW.md). Snapshot phải gồm untracked contents, manifest/hash/inventory và test evidence. Gemini chỉ review snapshot, chỉ ghi report theo handoff; không kích hoạt review tự động.

Lint frontend dùng Biome; TypeScript kiểm tra kiểu riêng. Các dependency được khóa trong `frontend/package-lock.json`. Chuỗi ESLint thử nghiệm ban đầu đã được thay trước khi bàn giao để loại bỏ cảnh báo dependency lint; không dùng `npm audit fix --force` hoặc override dependency major.

`.automation/` được giữ nguyên và bị tắt bằng `.automation/DESKTOP_ONLY`. Báo cáo lịch sử, schema baseline và EOL policy được bảo toàn. Chưa có auth, persistence, scaling, anti-cheat đầy đủ hoặc production deployment.
