# Codex Desktop → Antigravity Desktop → Codex Desktop

Quy trình thủ công trên Windows. Codex code/test ở nhánh `tu`; Gemini 4 Argon review độc lập và chỉ ghi report. Hai AI không merge `main`, push hoặc deploy database production. Không chạy CLI AI, không tái sử dụng token Desktop, không bật automation cũ.

## 1. Chọn đúng workspace và quyền reviewer

Mở `F:/MMRPG PNTT` ở chế độ **Local** trong Codex Desktop. Nhờ Codex xác nhận đường dẫn và nhánh `tu`; giữ thay đổi hiện có. Khi bàn giao, dừng mọi thao tác ghi source của Codex. Trong Antigravity, thêm/mở cùng folder và chọn Local, không tự tạo worktree mới.

Trước khi cho Gemini đọc workspace, người dùng kiểm tra quyền của project trong Antigravity: yêu cầu duyệt mọi `write_file(*)`; chặn terminal `command(*)`, MCP và browser actions; chỉ chấp thuận ghi chính xác `agentReport.md` và file mới dưới `reports/`. Không chấp thuận quyền ghi cả workspace/folder cha. Request Review mặc định **không** làm source chỉ đọc; cần kiểm tra quy tắc ghi file riêng. Chi tiết và nguồn: [.automation/DESKTOP_CAPABILITIES.md](.automation/DESKTOP_CAPABILITIES.md).

Nếu không thiết lập/xác minh được giới hạn này, không bắt đầu review trên workspace có thể ghi. Dùng bản sao source/diff đã loại secrets và được bảo vệ chỉ đọc; Gemini trả nội dung report, người dùng lưu hai bản report. Đây là fallback thủ công, không phải bảo đảm do prompt hay policy CLI tạo ra. Không thay quyền filesystem của repo gốc để thử.

## 2. Codex chuẩn bị bàn giao sau khi test

Gửi trong Codex Desktop:

> Đọc AGENTS.md, GEMINI_REVIEW.md và DESKTOP_WORKFLOW.md. Chỉ làm việc ở `tu`. Hoàn tất code, chạy test phù hợp và tự review. Không commit/push/merge/deploy hoặc gọi CLI AI. Tạo bộ bàn giao dưới `reports/<session>/`: `handoff-r0.md`, `diff-r0.patch`, `tests-r0.md`. Xác định base SHA trước tính năng và HEAD hiện tại, đường dẫn checkout, danh sách staged/unstaged và file untracked liên quan. Diff phải bao phủ thay đổi tích lũy từ base; file untracked phải được liệt kê và đọc riêng vì Git diff không chứa chúng. Ghi manifest SHA256 của toàn bộ source/config/test đủ điều kiện được bàn giao, gồm danh sách thêm/xóa; tính SHA256 cho chính manifest. Loại report/state/cache/secrets khỏi manifest source. Nếu không có test, ghi NOT_RUN và lý do, không kết luận game đã qua test. Sau đó dừng ghi source chờ Gemini review.

Base, session và bản manifest định danh snapshot phải rõ ràng trước khi review. HEAD là anchor, **không** định danh nội dung chưa commit. Không dùng “review HEAD” để bỏ qua thay đổi chưa commit. Không đưa `.env`, private keys, auth cache, `supabase/.temp/` hoặc secrets trong diff/log vào bàn giao. Nếu phát hiện secrets trong phạm vi cần review, dừng để xử lý, không gửi chúng cho reviewer.

## 3. Người dùng gửi review trong Antigravity

Chọn **Gemini 4 Argon** trong model picker; không có đúng model thì dừng. Gửi đường dẫn handoff cụ thể và prompt:

> Review độc lập đúng snapshot trong `reports/<session>/handoff-r0.md`. Đọc AGENTS.md, GEMINI_REVIEW.md, diff, test evidence và source thực tế liên quan, kể cả file untracked. Chỉ dùng file-reading tools; không sửa source/test/config/migration/rules/state/Git và không chạy terminal/MCP/browser. Chỉ ghi report qua file-writing tools được duyệt. Báo cáo provenance DESKTOP_MANUAL, session/base/HEAD anchor/parent, manifest SHA256, model được người dùng quan sát trong UI, thời điểm +07:00, file đã đọc, mọi trường finding theo GEMINI_REVIEW.md, test observations/evidence, verdict và trạng thái. r0 là review đầu, fix_attempts=0. Ghi file mới `reports/YYYY-MM-DD-<HEAD>-<session>-r0.md` trước, rồi ghi nội dung hoàn chỉnh giống vậy vào `agentReport.md`. Bảo toàn lịch sử và lưu bản lịch sử của report cũ nếu chưa có. Thiếu context/test evidence/model hoặc snapshot thay đổi thì BLOCKED/NOT_EVALUATED; không tạo PASS giả. Kết thúc bằng đường dẫn hai report đã lưu và manifest đã review.

Gemini phải xem thay đổi thực tế, không chỉ bản tóm tắt của Codex. Nếu xuất hiện yêu cầu ghi ngoài hai phạm vi report, từ chối; yêu cầu dừng review và kiểm tra source trước khi tiếp tục. Nếu công cụ ghi file cần chạy shell, dùng fallback ở bước 1.

## 4. Xác nhận review hoàn tất

Người dùng chờ Antigravity kết thúc, kiểm tra model picker, hai file report, scope và trạng thái. File tồn tại hay thông báo “done” không đủ. Chuyển lại Codex bằng cách gửi đường dẫn report; không có trigger/callback giữa hai Desktop được cấu hình.

## 5. Codex xác minh và sửa

Gửi trong Codex Desktop:

> Đọc `agentReport.md`, bản lịch sử mà nó chỉ ra và handoff của cùng session. Xác minh branch `tu`, base, round và manifest; tính lại toàn bộ manifest source để phát hiện file mới/xóa/sửa, kể cả untracked. Nếu source đã đổi trong lúc review, coi report là stale và chuẩn bị review lại, không áp dụng như review đã hoàn tất. Xác minh từng finding bằng source/test. Dừng với CRITICAL để Owner quyết định; không bỏ qua HIGH đã xác nhận. Chỉ sửa lỗi có bằng chứng, ghi rõ FIXED/REJECTED cùng lý do và test vào `reports/<session>/fix-response-r1.md`, không sửa report của Gemini hoặc quyền review. Chạy test và tự review; tạo handoff/diff/test evidence và manifest mới cho r1, vẫn giữ base gốc và session. Không commit/push/merge/deploy hoặc gọi CLI AI. Dừng ghi source để bàn giao lại.

## 6. Review lần hai và các lần tiếp theo

Quay lại Antigravity, giữ model, quyền và prompt review; thay đường dẫn bằng `handoff-r1.md`, kèm report r0 và `fix-response-r1.md`. Gemini kiểm tra lại finding cũ, lý do bác bỏ và regression trên **diff tích lũy từ base gốc**, rồi tạo report mới `...-r1.md` và cập nhật latest. Giữ report cũ nguyên vẹn.

Tối đa ba lượt sửa: r1, r2, r3 sau r0. Sau r3 còn lỗi bắt buộc thì BLOCKED và Owner quyết định; không mở chat mới để đặt lại budget. Sửa code không tự biến report cũ thành PASS. Report chỉ PASS khi không còn Required Actions và test phù hợp cho đúng snapshot đã thành công; trường hợp thiếu test phải ghi rõ blocker.

## 7. Owner quyết định cuối

Người dùng kiểm tra diff, test và report cuối. Hai AI không merge vào `main`; người dùng tự thực hiện merge khi chấp thuận, và tự quyết định commit/push riêng. Thay đổi source sau review làm kết luận cũ mất hiệu lực cho snapshot mới. Migration production luôn cần quyết định triển khai riêng.

## Lịch sử và khôi phục

Lịch sử nằm trong `reports/`, latest ở `agentReport.md`. Nếu trùng tên, dùng session/round hoặc hậu tố mới, không ghi đè lịch sử. Report cũ và `.agents/state/*` của engine CLI là lịch sử, không phải bộ đếm hay quyền kích hoạt Desktop. Khi app bị đóng, đọc lại handoff/report/dispositions để tiếp tục đúng session/base/budget; bộ bàn giao thiếu hoặc dở dang thì dừng xác minh, không chạy CLI `-Resume`.

Repo hiện có nhiều file chưa commit và chưa có ứng dụng/test game. Không tạo worktree review từ HEAD lúc này: nó sẽ thiếu file untracked và thay đổi chưa commit. Worktree riêng chỉ là lựa chọn về sau, sau khi người dùng cho phép chuẩn bị snapshot phù hợp; không checkout `tu` đồng thời ở hai worktree và không cho Codex viết ở detached HEAD.

Những việc còn thủ công: mở app/folder, chọn model/quyền, gửi prompt, chờ và xác nhận report, yêu cầu fix/re-review, kiểm tra budget và quyết định merge. Không có watcher, auto-fix, scheduled task, UI automation hay đồng bộ hội thoại giữa hai app được bật.
