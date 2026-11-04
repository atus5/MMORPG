# Codex Desktop → Antigravity Desktop → Codex Desktop

Quy trình thủ công trên Windows. Codex code/test ở nhánh `tu`; Gemini 4 Argon review độc lập và chỉ ghi report. Hai AI không merge `main`, push hoặc deploy database production. Không chạy CLI AI, không tái sử dụng token Desktop, không bật automation cũ.

## 1. Chọn đúng workspace và quyền reviewer

Mở `F:/MMRPG PNTT` ở chế độ **Local** trong Codex Desktop. Nhờ Codex xác nhận đường dẫn và nhánh `tu`; giữ thay đổi hiện có. Codex chuẩn bị một package snapshot riêng trước khi bàn giao. Trong Antigravity, mở package được chỉ định ở chế độ Local để đọc; không mở source live làm đầu vào review và không tự tạo worktree mới. Chỉ cấp quyền ghi các đường dẫn report đích, không cấp quyền ghi package/source.

Trước khi cho Gemini đọc workspace, người dùng kiểm tra quyền của project trong Antigravity: yêu cầu duyệt mọi `write_file(*)`; chặn terminal `command(*)`, MCP và browser actions; chỉ chấp thuận ghi chính xác `agentReport.md` và file mới dưới `reports/`. Không chấp thuận quyền ghi cả workspace/folder cha. Request Review mặc định **không** làm source chỉ đọc; cần kiểm tra quy tắc ghi file riêng. Chi tiết và nguồn: [.automation/DESKTOP_CAPABILITIES.md](.automation/DESKTOP_CAPABILITIES.md).

Nếu không thiết lập/xác minh được giới hạn này, không bắt đầu review trên workspace có thể ghi. Dùng bản sao source/diff đã loại secrets và được bảo vệ chỉ đọc; Gemini trả nội dung report, người dùng lưu hai bản report. Đây là fallback thủ công, không phải bảo đảm do prompt hay policy CLI tạo ra. Không thay quyền filesystem của repo gốc để thử.

## 2. Codex chuẩn bị bàn giao sau khi test

Gửi trong Codex Desktop:

> Đọc AGENTS.md, GEMINI_REVIEW.md và DESKTOP_WORKFLOW.md. Chỉ làm việc ở `tu`. Hoàn tất code, test và tự review, không commit/push/merge/deploy hoặc gọi CLI AI. Tạo package mới `reports/<session-UUID>/r0-<package-UUID>/` bằng chế độ create-new, không tái sử dụng thư mục có sẵn. Lưu `handoff-r0.md`, `diff-r0.patch`, `tests-r0.md`, inventory included/excluded và `snapshot/` chứa nguyên byte tất cả file nguồn/config/test/tài liệu liên quan, gồm đầy đủ nội dung untracked và bản trước của file bị xóa nếu cần. Lưu reviewed_commit_sha/HEAD anchor, parent/base, Git status staged/unstaged/untracked, session/round. Tính SHA256 trên byte đã sao chép bằng công cụ checksum cục bộ của Codex, ghi tên cơ chế và kết quả vào manifest; kiểm tra bản sao khớp nguồn khi chốt gói. Lưu manifest và SHA256 của manifest, giữ nguyên package sau bàn giao. Thiếu test thì NOT_RUN cùng lý do, không tuyên bố game đã qua test.

Base, session và bản manifest định danh snapshot phải rõ ràng trước khi review. HEAD là anchor, **không** định danh nội dung chưa commit. Không dùng “review HEAD” để bỏ qua thay đổi chưa commit. Không đưa `.env`, private keys, auth cache, `supabase/.temp/` hoặc secrets trong diff/log vào bàn giao. Nếu phát hiện secrets trong phạm vi cần review, dừng để xử lý, không gửi chúng cho reviewer.

Manifest ghi đường dẫn tương đối `/`, loại file/status, số byte và hash của từng payload theo thứ tự đường dẫn ordinal. File nguồn giữ nguyên byte và CRLF/LF; chỉ JSON manifest được chuẩn hóa UTF-8/LF theo quy ước ghi trong handoff. Không đưa manifest vào chính nó: digest của manifest nằm ở file riêng; handoff tham chiếu digest và không nằm trong tập payload gây vòng tham chiếu. Inventory chỉ rõ file được gồm/loại và lý do. `git diff` chỉ phục vụ phần tracked; nội dung untracked bắt buộc có trong `snapshot/`, không chỉ có tên/hash. Mỗi vòng giữ bản sao cũ để so sánh cả các file chưa từng được Git lưu.

“Immutable” ở đây là package chốt, create-only và không sửa sau bàn giao; nếu cần sửa, tạo package UUID mới. Read-only attribute là hỗ trợ chống sửa nhầm, không phải sandbox bảo mật. Codex/Owner xác minh lại checksum bằng `Get-FileHash -Algorithm SHA256` hoặc `hashlib.sha256` trên byte thực. Gemini không được yêu cầu chạy checksum qua shell. Hiện chưa xác minh được công cụ checksum chỉ đọc được hỗ trợ trong Antigravity Desktop; `read_file` và việc so sánh chuỗi hash không tự chứng minh SHA256 của byte gốc.

## 3. Người dùng gửi review trong Antigravity

Chọn **Gemini 4 Argon** trong model picker; không có đúng model thì dừng. Gửi đường dẫn handoff cụ thể và prompt:

> Review độc lập package trong handoff được chỉ định. Đọc bản AGENTS.md/GEMINI_REVIEW.md trong snapshot, diff, full contents của file tracked/untracked được cung cấp, evidence vòng trước và test results. Chỉ review snapshot, không dùng workspace live thay thế. Không chạy command/MCP/browser hoặc sửa package/source/state/Git. Trong report, chép giá trị manifest nhận từ Codex vào `hashes_supplied_by_codex`; ghi riêng `hashes_independently_verified` với tên tool và kết quả thực nếu có, hoặc `not_independently_verified` cùng lý do khi không có checksum tool. Không tuyên bố crypto verification chỉ từ read_file hay hash Codex đưa. Giữ metadata/finding/test fields trong GEMINI_REVIEW.md. Ghi history mới ở exact path trong handoff theo mẫu `reports/YYYY-MM-DD-<HEAD>-<session-UUID>-<package-UUID>-r0.md`, với `overwrite=false`/`Overwrite: false` nếu tool hỗ trợ, rồi mới cập nhật latest. Nếu tool không có create-only đáng tin cậy, trả text để Owner lưu lịch sử bằng cơ chế create-new. Kết thúc bằng đường dẫn report và package đã đọc; không tạo PASS giả.

Gemini phải xem thay đổi thực tế, không chỉ bản tóm tắt của Codex. Nếu xuất hiện yêu cầu ghi ngoài hai phạm vi report, từ chối; yêu cầu dừng review và kiểm tra source trước khi tiếp tục. Nếu công cụ ghi file cần chạy shell, dùng fallback ở bước 1.

## 4. Xác nhận review hoàn tất

Người dùng chờ Antigravity kết thúc, kiểm tra model picker, hai file report, package/round và trạng thái. File tồn tại hay “done” không đủ. Report phải phân biệt hash được cung cấp, hash được tool tự kiểm chứng và hash chưa tự kiểm chứng. Việc Gemini không có checksum tool là giới hạn cần công khai, không phải lý do để bật shell. Review nội dung có thể hoàn tất với giới hạn này nếu đủ context/evidence; checksum cuối và liên hệ với source live do Codex/Owner kiểm tra. Chuyển đường dẫn report về Codex; không có callback tự động.

## 5. Codex xác minh và sửa

Gửi trong Codex Desktop:

> Đọc report lịch sử và package được review của cùng session. Xác minh branch `tu`, base/round; dùng checksum tool của Codex kiểm tra package còn khớp manifest và so sánh snapshot với source hiện tại, gồm untracked. Nếu source live đổi, report vẫn chỉ đánh giá package cũ, không coi là approval cho source mới. Xác minh từng finding bằng code/test. Dừng CRITICAL để Owner quyết định, không bỏ qua HIGH đã xác nhận. Sửa lỗi có bằng chứng, ghi FIXED/REJECTED cùng lý do/test trong `fix-response-r1.md` của package mới; không sửa review cũ. Chạy test và tạo snapshot/diff/inventory/manifest mới cho r1, cùng base/session. Không commit/push/merge/deploy hoặc gọi CLI AI. Dừng ghi package sau khi chốt.

## 6. Review lần hai và các lần tiếp theo

Quay lại Antigravity, giữ model/quyền và chọn package UUID mới chứa `handoff-r1.md`, bản review r0 và `fix-response-r1.md`. Gemini kiểm tra finding cũ, lý do bác bỏ và regression trên **snapshot/diff tích lũy từ base gốc**, rồi tạo history mới có cùng session, package UUID mới và round r1. Giữ package/report cũ nguyên vẹn; không tái dựng nội dung untracked cũ từ HEAD vì Git chưa lưu chúng.

Tối đa ba lượt sửa: r1, r2, r3 sau r0. Sau r3 còn lỗi bắt buộc thì BLOCKED và Owner quyết định; không mở chat mới để đặt lại budget. Sửa code không tự biến report cũ thành PASS. Report chỉ PASS khi không còn Required Actions và test phù hợp cho đúng snapshot đã thành công; trường hợp thiếu test phải ghi rõ blocker.

## 7. Owner quyết định cuối

Người dùng kiểm tra diff, test và report cuối. Hai AI không merge vào `main`; người dùng tự thực hiện merge khi chấp thuận, và tự quyết định commit/push riêng. Thay đổi source sau review làm kết luận cũ mất hiệu lực cho snapshot mới. Migration production luôn cần quyết định triển khai riêng.

## Lịch sử và khôi phục

Lịch sử dùng duy nhất mẫu `reports/YYYY-MM-DD-<HEAD>-<session-UUID>-<package-UUID>-r<round>.md`, latest ở `agentReport.md`. Nếu trùng tên, dừng và chọn UUID output mới, không ghi đè; dùng `overwrite=false`/create-new khi được hỗ trợ. Cờ đó áp dụng cho history, không áp dụng cho cập nhật latest có chủ ý sau khi history đã lưu. Nếu thiếu create-only thì Owner lưu text bằng cơ chế exclusive create; không dùng check-then-overwrite làm bảo đảm chống race. Report cũ và `.agents/state/*` của CLI là lịch sử, không phải bộ đếm Desktop. Khi app đóng, mở lại package/handoff/report đúng session/base/budget; không dùng CLI `-Resume`.

Repo hiện có nhiều file chưa commit và chưa có ứng dụng/test game. Không tạo worktree review từ HEAD lúc này: nó sẽ thiếu file untracked và thay đổi chưa commit. Worktree riêng chỉ là lựa chọn về sau, sau khi người dùng cho phép chuẩn bị snapshot phù hợp; không checkout `tu` đồng thời ở hai worktree và không cho Codex viết ở detached HEAD.

Những việc còn thủ công: mở app/folder, chọn model/quyền, gửi prompt, chờ và xác nhận report, yêu cầu fix/re-review, kiểm tra budget và quyết định merge. Không có watcher, auto-fix, scheduled task, UI automation hay đồng bộ hội thoại giữa hai app được bật.
