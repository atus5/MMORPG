# Kiểm chứng tích hợp Desktop — 2026-11-04

Tách bằng chứng trên máy, tính năng được tài liệu chính thức mô tả và những thao tác chưa thử trong UI. Không gọi CLI AI, không khởi chạy model hoặc dùng tự động hóa giao diện trong lần kiểm tra này.

## Bằng chứng cục bộ

- Antigravity Desktop đang chạy từ `C:/Users/Admin/AppData/Local/Programs/antigravity/Antigravity.exe`; FileVersion `2.28.2`, ProductVersion `2.28.2.0`; registry và shortcut cũng nhận diện Antigravity 2.28.2.
- Tìm thấy Codex extension `openai.chatgpt` phiên bản `26.1021.22027` và host đang chạy. Đây là phiên bản extension, không phải bằng chứng số phiên bản Codex Desktop độc lập. Chưa tìm thấy phiên bản standalone qua inventory tiến trình, Appx của tài khoản hiện tại, shortcut và các vị trí ứng dụng đã kiểm tra. Điều này không chứng minh ứng dụng không được cài; người dùng xem About trong Desktop để xác nhận.
- Repo `F:/MMRPG PNTT`, nhánh `tu`, HEAD `89fb280812aa0643edb9fc6f3fcbd8998b2cc7d1`; chỉ có một worktree đăng ký. Có thay đổi chưa commit/untracked. Không có `core.hooksPath` đang cấu hình tại thời điểm kiểm tra. Không tạo/switch worktree hoặc sửa cấu hình ứng dụng.
- Không đọc token, cache đăng nhập hoặc cấu hình xác thực Desktop. Không thử tái sử dụng tài khoản qua client khác. Việc Gemini 4 Argon xuất hiện và được chọn trong tài khoản Antigravity hiện tại phải do người dùng xác nhận trong UI; chưa có một review Desktop thật được gọi ở đây.

## Workspace và worktree

Tài liệu Windows của OpenAI mô tả project local, Git, preview và worktree. Đây là hỗ trợ được công bố; kiểm chứng UI trên đúng bản Codex Desktop của người dùng còn thiếu. [OpenAI Windows Desktop](https://learn.chatgpt.com/docs/windows/windows-app)

Codex có Local/Worktree và Handoff nội bộ. Worktree mới có thể ở detached HEAD; Git không cho checkout một branch ở hai worktree cùng lúc. Handoff không phải cơ chế chuyển chat sang Antigravity. Với quy tắc Codex chỉ viết trên `tu`, chọn Local checkout hiện tại; không tạo worktree viết mã detached. [OpenAI worktrees](https://learn.chatgpt.com/docs/environments/git-worktrees)

Antigravity có project gồm folder/Git checkout, lựa chọn Local hoặc New worktree. Mở cùng checkout trong hai app cho phép đọc cùng file; an toàn phụ thuộc việc không có hai writer và có quyền reviewer phù hợp, không phải một khóa liên ứng dụng được bảo đảm. [Antigravity projects](https://antigravity.google/docs/projects)

Worktree reviewer riêng là lựa chọn được tài liệu hỗ trợ, chưa tạo/thử ở repo này. Nó phải dựa trên snapshot đã chuẩn bị đúng; các thay đổi chưa commit, file untracked và report trong worktree khác không tự đồng bộ. Reviewer có thể dùng detached worktree chỉ đọc ở SHA được bàn giao sau khi Owner cho phép; Codex vẫn viết trên `tu`. Người dùng phải chuyển report giữa hai thư mục và xác minh identity của snapshot.

## Đọc source và chỉ ghi report

Antigravity công bố các quy tắc `read_file`, `write_file`, `command` và MCP theo Deny > Ask > Allow. Workspace có thể ghi theo mặc định; preset Request Review không tự chặn sửa source. Người dùng cần cấu hình Ask `write_file(*)`, Deny `command(*)`, MCP/browser actions, rồi chỉ duyệt ghi exact `agentReport.md` và file lịch sử dưới `reports/`. Không Allow cả project hoặc chấp thuận mở rộng target sang folder cha. Không đặt Deny ghi cả project rồi mong Allow report vượt qua Deny. [Antigravity App permissions](https://antigravity.google/docs/permissions)

Đây là cấu hình thủ công đề xuất dựa trên tài liệu, chưa được đặt hoặc kiểm thử qua UI trên máy. Trước review writable workspace, người dùng kiểm tra các rule có hiệu lực ở đúng project và không có quyền rộng cũ; nếu chưa xác minh được thì dừng và dùng snapshot được bảo vệ chỉ đọc, Gemini trả text để người dùng lưu report. Prompt và `.automation/reviewer-deny-tools.toml` không áp quyền cho Antigravity Desktop.

Gemini chỉ ghi báo cáo vào repo, không sửa code/test/config/migration/state/Git. Codex đọc report từ filesystem khi người dùng yêu cầu; không có bộ nhận report tự động. Bằng chứng hoàn tất là report lịch sử và latest khớp nhau, đúng session/manifest, đầy đủ nội dung và source không đổi trong khi review — không chỉ là sự kiện agent dừng.

## Trigger từ ứng dụng khác và nhận completion

- **Được tài liệu xác nhận:** Codex có deep link `codex://...` để mở chat và điền prompt/path; người dùng vẫn phải gửi prompt. Chưa thử URI handler trên bản Desktop cục bộ. Đây không phải vòng review liên ứng dụng. [OpenAI desktop commands](https://learn.chatgpt.com/docs/reference/commands)
- **Được tài liệu xác nhận, chưa cấu hình:** Antigravity App có lifecycle hooks, gồm Stop. Stop chỉ báo vòng agent dừng, không chứng minh review đã hoàn tất hoặc PASS. Không cài hook/watcher trong tác vụ này. [Antigravity App hooks](https://antigravity.google/docs/hooks)
- **API riêng, ngoài quy trình này:** OpenAI công bố app-server cho client tích hợp và streamed events, nhưng đó không chứng minh hai Desktop hiện có nối được trực tiếp; command app-server là experimental. Không khởi chạy server/SDK hoặc kết nối endpoint nội bộ. [OpenAI app-server](https://learn.chatgpt.com/docs/app-server)
- **Chưa xác minh:** API Desktop-to-Desktop ổn định để Codex gửi việc sang đúng phiên Antigravity/Gemini 4 Argon và nhận kết quả review có định danh. Không kết luận mọi API đều không tồn tại; không có bridge đáp ứng yêu cầu đã được xác minh/cấu hình ở đây.
- **Cần thao tác người dùng:** mở app, project và chat; chọn model/quyền; gửi prompt; kiểm tra hai file report và chuyển lại Codex; yêu cầu re-review; chấp thuận merge bằng tay.

Không dùng simulated clicks, OCR, scraping transcript, private protocol, trích token hoặc tự chuyển model để lấp khoảng trống. Không dùng UI automation: khả năng bấm nhầm model/project, duyệt nhầm quyền và nhận nhầm completion không tạo được một cầu nối đáng tin cậy.

## Thành phần cũ được bảo toàn

CLI controller/adapters/config, hai JSON schemas, policy chặn tools, fixture suite, hook source và report/state history vẫn còn. `.automation/DESKTOP_ONLY` chặn adapter trước khi tìm/chạy CLI, chặn probe và Enable, và làm trạng thái enabled luôn false. Giá trị `auto_fix: true` trong config cũ chỉ là cấu hình thử nghiệm bất hoạt, không điều khiển Desktop.

Receipt cũ ghi 29 fixture pass là lịch sử, không xác nhận Desktop integration. Không chạy lại suite cũ trong tác vụ này vì nó tạo commit trong repo tạm và ghi đè receipt; dùng bài kiểm tra policy mới không gọi AI/Git và không thay report/state lịch sử. Không sửa, xóa hoặc tái cấp hiệu lực cho receipt cũ.
