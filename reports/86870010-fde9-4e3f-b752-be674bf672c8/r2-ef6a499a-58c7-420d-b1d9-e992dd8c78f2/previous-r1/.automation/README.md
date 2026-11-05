# Desktop-only: quy trình hiện hành

Dùng [DESKTOP_WORKFLOW.md](../DESKTOP_WORKFLOW.md): Codex Desktop code/test trên `tu`, người dùng bàn giao cho Gemini 4 Argon trong Antigravity Desktop, rồi đưa report lại Codex. Gemini chỉ ghi `agentReport.md` và `reports/`. Không có auto-invocation, auto-fix, commit, push, merge hoặc deploy được bật.

Kết quả kiểm chứng, phiên bản cục bộ và giới hạn tích hợp: [DESKTOP_CAPABILITIES.md](DESKTOP_CAPABILITIES.md). Workspace/report là điểm bàn giao qua file; việc mở app, chọn model/quyền và xác nhận kết quả vẫn do người dùng.

`.automation/DESKTOP_ONLY` là chốt tắt cho thành phần CLI thử nghiệm: adapters bị chặn trước CLI/authentication, probe không được chạy, Enable bị từ chối, và `Test-TuEnabled` luôn false. Không bỏ marker để chạy quy trình cũ. `config.json` được giữ nguyên để bảo toàn compatibility với fixture; `auto_fix: true` trong đó không có tác dụng trong workflow Desktop.

Không chạy Codex/Gemini CLI, probe, xác thực CLI, OAuth workaround, cài hook hoặc `-Resume` cũ. Không dùng receipt CLI để suy ra quyền model/quyền ghi của Desktop. Report/state cũ được giữ nguyên và không phải trạng thái Desktop hiện hành. JSON schemas, report fields, fixture tests, policy và Git safety vẫn được bảo toàn; policy CLI không tự áp vào Desktop.

Kiểm tra policy mới không gọi AI/Git và không tạo commit: `powershell -NoProfile -File .automation/tests/desktop-policy.tests.ps1`. Suite `run-tests.ps1` bên dưới vẫn được giữ, nhưng không chạy trong tác vụ cấm commit này vì nó tạo commit ở các repo tạm và ghi receipt mới.

---

# Lưu trữ: Vận hành CLI code – review – fix (thử nghiệm, không hoạt động)

**Phần còn lại là tài liệu của thiết kế trước, giữ để tham khảo. Các lệnh cài đặt/xác thực/probe/bật CLI bên dưới không phải hướng dẫn cho workflow hiện tại và không được thực hiện theo yêu cầu Desktop-only.**

Hệ thống đang được chuẩn bị, **chưa bật hook hoặc auto-fix thật**. Product Owner quyết định kích hoạt. Không có lệnh push, merge hay triển khai database trong controller.

## Các thành phần

- `.automation/orchestrator.ps1`: entry point PowerShell 5.1 trên Windows.
- `controller.ps1`: state machine, lock độc quyền, kiểm tra SHA, test, commit và báo cáo.
- `invoke-gemini.ps1`: gọi Gemini CLI headless đúng `gemini-4-argon`, không fallback.
- `invoke-codex.ps1`: gọi `codex exec` chỉ đọc để nhận JSON chứa nội dung file đề xuất; controller áp dụng sửa đổi.
- `review.schema.json`, `fix.schema.json`: hợp đồng dữ liệu; controller còn kiểm tra SHA, file, line, severity và verdict.
- `.agents/agents/gemini-reviewer.md`: mô tả vai trò dành cho controller. File này không tự đăng ký một Gemini agent trong IDE.
- `.agents/skills/gemini-reviewer/SKILL.md`: hướng dẫn vận hành có thể tái sử dụng.

Chỉ `.githooks/post-commit` được chuẩn bị trong repo. Việc có file hook không có nghĩa Git đã dùng hook đó.

## Quyền và giới hạn

Gemini chạy trong thư mục tạm riêng, nhận snapshot qua stdin. Controller cung cấp AGENTS.md, GEMINI_REVIEW.md, diff tích lũy từ parent gốc và toàn bộ file text được Git theo dõi đủ điều kiện, gồm bản gốc của file đã xóa. Secret/cache/report/state không được gửi. Nếu file không đọc được, có symlink/submodule, binary, context vượt giới hạn hoặc có dấu hiệu secret, controller dừng; không cắt ngầm rồi kết luận PASS.

Adapter Gemini ghim CLI `0.66.0`. Nó tạo home riêng với ACL chỉ cho tài khoản hiện tại và SYSTEM, chỉ sao chép cache OAuth cần thiết, tắt hooks/MCP/extensions và dùng policy `deny` cho mọi tool. Cache tạm được xóa trong `finally`. Nếu process bị kill cưỡng bức có thể còn thư mục `%TEMP%/tu-ai-*`: kiểm tra process đã dừng, kiểm tra chính xác đường dẫn rồi xóa bằng PowerShell. Không xóa cache OAuth gốc.

Policy được nạp ở user tier trong home sạch. Nếu `C:/ProgramData/gemini-cli` có file cấu hình/policy có thể ghi đè quyền, adapter dừng để kiểm tra thủ công. Không thay ACL của cấu hình hệ thống, không hạ kiểm tra bảo mật, không dùng YOLO. Metadata JSON phải xác nhận chỉ đúng model yêu cầu và `tools.totalCalls = 0`; model tự nói tên của nó không đủ làm bằng chứng. Khác phiên bản CLI hoặc thiếu metadata thì BLOCKED và cần kiểm chứng adapter lại.

Codex cũng chạy trong thư mục tạm, sandbox `read-only`, không nạp user config/MCP, shell tool bị tắt. Controller từ chối tool events và chỉ nhận các file thay thế hoàn chỉnh theo schema. Codex không được cấp repo làm workspace có thể ghi. Controller chỉ cho sửa `frontend/`, `backend/`, `supabase/migrations/`, `tests/`; chặn traversal, symlink/junction, secrets và file quy tắc/automation/Git. Chỉ controller chạy các lệnh test cố định do Owner cấu hình và tạo commit sau test thành công. Việc gọi CLI có thể dùng quota của tài khoản đã đăng nhập.

Không có quyền đọc database Cloud trong auto-review. Gemini chỉ đánh giá SQL, migration và metadata đã cung cấp; kiểm tra database thật phải thực hiện riêng bằng phương thức chỉ đọc. Tuyệt đối không tự áp dụng migration production.

## Kiểm tra và cài đặt CLI

Các lệnh chạy tại root repo:

```powershell
codex --version
codex login status
gemini --version
powershell -NoProfile -File .automation/check-environment.ps1
powershell -NoProfile -File .automation/check-environment.ps1 -Probe
```

`-Probe` gọi hai CLI thật với yêu cầu nhỏ, không sửa source. Nó lưu `.agents/state/live-probes.json`; lỗi xác thực, quota, model, JSON hoặc read-only là BLOCKED. Probe không phải một lần review source và không tạo PASS cho commit.

Nếu thiếu CLI, cài theo tài liệu chính thức: [Codex CLI](https://developers.openai.com/codex/cli/), [Gemini CLI installation](https://geminicli.com/docs/get-started/installation/). Nếu thiếu đăng nhập, chạy `codex login` hoặc mở `gemini` và hoàn thành đăng nhập tương tác tại máy. Không gửi API key/password trong chat hoặc lưu vào config. Adapter hiện hỗ trợ Gemini OAuth cá nhân hoặc `GEMINI_API_KEY` do người dùng tự đặt trong môi trường; không giả định đăng nhập Antigravity cấp quyền gọi model qua Gemini CLI.

Nếu API báo không có quyền `gemini-4-argon`, kiểm tra tài khoản/quyền model với Google và chạy lại probe. Không thay bằng model khác. Model được Google công bố tại [Gemini 4 Argon](https://ai.google.dev/gemini-api/docs/models/gemini-4-argon); công bố model không chứng minh tài khoản hiện tại được truy cập.

Kiểm tra thực tế ngày 2026-11-04: Codex headless đã trả JSON hợp lệ. Gemini CLI `0.66.0` với OAuth cá nhân bị Google từ chối bằng `IneligibleTierError` / `UNSUPPORTED_CLIENT` (client không còn được hỗ trợ cho tier hiện tại). Do đó chưa xác minh được quyền model hoặc live read-only probe. Cần xử lý phương thức xác thực/quyền tài khoản được Google hỗ trợ. Có thể chọn Gemini API key trong CLI và đặt `GEMINI_API_KEY` tại máy nếu tài khoản có quyền và bạn đồng ý chi phí; không sao chép token Antigravity, không đổi model, không đưa key vào repo/chat. Chạy lại `check-environment.ps1 -Probe` sau khi xử lý. Chưa cài/nâng cấp công cụ hoặc đổi phương thức xác thực thay người dùng.

## Kiểm thử trước kích hoạt

```powershell
powershell -NoProfile -File .automation/orchestrator.ps1 -DryRun
powershell -NoProfile -File .automation/tests/run-tests.ps1
```

Dry-run không gọi AI, ghi report/state hay sửa Git. Fixture suite dùng repo tạm không remote, engines mô phỏng có nhãn FIXTURE, commit/test/hook thực trong repo tạm. Nó không gọi AI hoặc cố tình tạo lỗi trong source game. Receipt `.agents/state/fixture-tests.json` ghi rõ đây chỉ là kiểm thử controller.

Hai receipt phải PASSED và khớp fingerprint của script/quy tắc/config hiện tại. Sau khi sửa controller hoặc cấu hình, chạy lại các kiểm tra; không sửa receipt bằng tay để vượt gate. PASS fixture không thay thế probe CLI thật hoặc review source thật.

## Cấu hình test của game

Hiện repo chưa có ứng dụng hoặc test của game. `test_commands` đang rỗng; đây là blocker có chủ ý cho kích hoạt thật. Sau khi có bộ test, Owner cấu hình danh sách đối tượng `executable` và `arguments`. Dùng executable native, không dùng chuỗi shell do AI sinh ra. Ví dụ khi backend đã có pytest và frontend đã có runner phù hợp:

```json
[
  {"executable":"python", "arguments":["-m", "pytest", "backend/tests"]},
  {"executable":"node", "arguments":["frontend/node_modules/vitest/vitest.mjs", "run", "--root", "frontend"]}
]
```

Đây là ví dụ cấu hình, không phải khẳng định pytest/Vitest đã được cài. Test chạy từ root, môi trường đã bỏ credentials của database và CLI. Chuẩn bị test local có transaction/concurrency/idempotency, Auth/RLS với hai người chơi, WebSocket/heartbeat/AFK và regression phù hợp chức năng. Không cấu hình test có tác dụng deploy/push hoặc dùng database production.

## Bật / tắt

Chỉ sau khi Owner xác nhận, app test commands có thật, cả hai receipt PASSED và các file chuẩn bị đã được commit trên `tu` với worktree sạch:

```powershell
powershell -NoProfile -File .automation/install-hooks.ps1
# Chỉ sau xác nhận của Product Owner:
powershell -NoProfile -File .automation/install-hooks.ps1 -Enable -ProductOwnerApproved
```

Lệnh đầu chỉ in kế hoạch. Lệnh Enable cài `core.hooksPath=.githooks` local và ghi quyền kích hoạt vào state bị Git bỏ qua, không sửa config được theo dõi. Nếu đã có hook hoặc hooksPath khác, installer dừng để tích hợp thủ công và bảo toàn hook cũ. Tham số `-ProductOwnerApproved` là lời xác nhận của người vận hành, không được agent tự sử dụng khi Owner chưa đồng ý.

```powershell
powershell -NoProfile -File .automation/install-hooks.ps1 -Disable
# Tắt và khôi phục local hooksPath trước khi cài:
powershell -NoProfile -File .automation/install-hooks.ps1 -Uninstall
```

Disable ngăn lượt mới và được kiểm tra lại trước review/fix/commit; một CLI đang chạy có thể cần hết timeout mới dừng. Không xóa report hay state. Hook chạy đồng bộ, độc lập IDE; một commit có thể chờ hết chuỗi review/test có giới hạn. Post-commit không thể hủy commit gốc: xem trạng thái báo cáo nếu BLOCKED. Controller không push, kể cả `origin/tu`.

## State, vòng lặp và khôi phục

- `.agents/state/review-lock.json`: FileShare.None trong suốt session; file có thể tồn tại khi idle. Sự tồn tại của file không có nghĩa lock còn bị giữ. OS giải phóng handle khi process chết.
- `review-status.json`: session ID, original SHA, current SHA, parent/base SHA, phase, số review, số fix, test và trạng thái.
- `last-reviewed-commit.txt`: SHA chỉ được ghi sau review hợp lệ và test thành công.
- Commit chỉ chứa `agentReport.md`, `reports/*`, `.agents/state/*` được bỏ qua. Controller dùng biến `TU_AUTOMATION_INTERNAL=1` cho commit sửa lỗi; hook không khởi chạy controller thứ hai.
- Mỗi chain có tối đa ba lượt fix, bao gồm lượt lỗi hoặc bị crash sau khi đã tiêu thụ budget. Review lại luôn so với base gốc, không chỉ commit sửa cuối cùng.
- CRITICAL, lỗi AI, JSON sai, model khác, test fail, worktree bẩn, HEAD thay đổi, finding thiếu bằng chứng hoặc hết budget đều dừng ở BLOCKED. Rejected finding không được tự coi là resolved.

Sau crash/lỗi: tắt automation nếu cần, đọc `agentReport.md` và state, bảo toàn source/report. Khi đã xác minh process cũ dừng và xử lý nguyên nhân, dùng:

```powershell
powershell -NoProfile -File .automation/orchestrator.ps1 -Resume
```

Resume giữ session, base và budget. Nếu đã có sửa đổi nhưng test thất bại, controller không reset/clean hoặc tự commit chúng. Owner kiểm tra, sửa/test rồi commit trên `tu`; Resume chấp nhận HEAD mới chỉ khi nó là descendant của SHA đang chờ. Nếu đã hết ba lượt fix, Owner phải xử lý source thủ công; review PASS sau đó vẫn có thể kết thúc session. Không sửa/xóa state để tự làm mới budget.

## Xem báo cáo và giới hạn

`agentReport.md` là báo cáo mới nhất. Mỗi kết quả được lưu ở `reports/YYYY-MM-DD-<sha>.md` và JSON tương ứng. Nếu cùng SHA có nhiều kết quả, tên thêm session/ID để không ghi đè lịch sử. Báo cáo gồm SHA/parent/base, model thực tế từ CLI metadata, thời điểm `+07:00`, findings, file đã đọc, test observations, test do controller chạy, số lượt sửa và trạng thái cuối.

Không ghi raw CLI output/prompt hoặc stdout của test vào log. Secret-pattern detection chỉ là bộ lọc bổ sung; vẫn không được đưa secrets vào source. Binary/monorepo lớn, Vertex auth, hệ điều hành khác Windows và CLI khác bản ghim cần bổ sung adapter rồi kiểm thử. Kiểm thử mock không chứng minh chất lượng review của model, hay toàn bộ pipeline thật đã sẵn sàng. Các thay đổi hạ tầng/quyền của chính automation cần Owner kiểm tra thủ công.

Nguồn kỹ thuật: [Codex non-interactive](https://learn.chatgpt.com/docs/non-interactive-mode), [Gemini headless JSON](https://geminicli.com/docs/cli/headless/), [Gemini policy engine](https://geminicli.com/docs/reference/policy-engine/).
