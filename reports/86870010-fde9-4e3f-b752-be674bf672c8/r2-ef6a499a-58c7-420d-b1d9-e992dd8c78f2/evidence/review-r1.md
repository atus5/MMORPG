# Independent Code Review Report — Re-Review R1 (Desktop Workflow Migration)

- **Project:** Tu Tiên Online
- **Provenance:** `DESKTOP_MANUAL` (Independent Re-Review `r1` — Desktop Workflow Migration)
- **Session ID:** `86870010-fde9-4e3f-b752-be674bf672c8`
- **Round / Fix attempts consumed:** `r1` (`1/3`)
- **Absolute checkout:** `f:\MMRPG PNTT`
- **Branch:** `tu`
- **Commit SHA (`HEAD` anchor):** `89fb280812aa0643edb9fc6f3fcbd8998b2cc7d1` (`first commit`)
- **Parent SHA:** `null` (root commit)
- **Chain base SHA:** `4b825dc642cb6eb9a060e54bf8d69288fbee4904` (empty tree) / `89fb280812aa0643edb9fc6f3fcbd8998b2cc7d1` (`HEAD` anchor)
- **Worktree / Manifest identity:**
  - **Working tree status:** Dirty (`WORKTREE_NOT_CLEAN` — 1 modified tracked file `README.md`, 23 untracked source/doc/automation files, plus 5 state files and 3 report files; 0 changes occurred during `r1` review window).
  - **Automation Fingerprint (`Get-TuFingerprint`):** `aafe118128abbac029d3982214abff9720417250680a54df75ed7f2be4bd7ce7` (changed from `f5eae8cf2ab4b0b29a8df434af09e1b68bb5abae1a31f190a324ad26787a60df` in `r0`).
  - **Reviewed 24-File Snapshot Manifest SHA256:** `081695e6be2d07660e7c059b0a249b50a2431ffb2fd12ece3c09c272cde3c8b4`
- **Reviewed by:** Gemini 4 Argon (`gemini-4-argon`)
- **UI-observed model & evidence:** User-selected `Gemini 4 Argon (High)` in Antigravity Desktop (`<USER_SETTINGS_CHANGE>` UI metadata; not CLI API attestation)
- **Review date:** `2026-11-04T12:07:30+07:00`
- **Verdict:** `CHANGES_REQUIRED` *(Desktop Workflow Migration `r1`: `CHANGES_REQUIRED`; Overall Game Application: `BLOCKED` / `NOT_EVALUATED` — game source & migrations do not exist yet)*
- **Final status:** `CHANGES_REQUIRED`
- **Reason:** Finding `BASE-001` (`HIGH`) và `BASE-003` (`LOW`) từ vòng `r0` đã được khắc phục hoàn toàn; việc khóa CLI qua `.automation/DESKTOP_ONLY` hoạt động đúng trên các adapter thực thi. Tuy nhiên, còn **1 finding cũ chưa được sửa (`BASE-002` — `MEDIUM`)** và phát hiện **2 finding `MEDIUM` mới (`DESK-001`, `DESK-002`)** cùng **1 đề xuất `LOW` (`DESK-003`)** liên quan đến độ phủ của bộ test chính sách mới `.automation/tests/desktop-policy.tests.ps1` và tính toàn vẹn của gói bàn giao (handoff) thực tế.

---

## 1. Summary & Snapshot Identity

Phiên **Re-Review `r1` (vòng sửa lỗi `1/3`)** kiểm tra độc lập toàn bộ quá trình chuyển đổi từ thiết kế CLI automation cũ sang quy trình bàn giao thủ công **Codex Desktop → Antigravity Desktop → Codex Desktop**.

### Thay đổi thực tế trên đĩa của Codex giữa `r0` và `r1`:
So sánh trực tiếp timestamps và SHA256 với snapshot `r0` xác nhận 4 file đã được Codex thêm mới hoặc cập nhật sau đợt ghi lúc `11:55:24+07:00`:
1. `DESKTOP_WORKFLOW.md` *(tạo mới lúc `11:57:03+07:00`, SHA256: `54c904a560fd141f39b3fb1621f6b122deeeaf20de727a8dadee48fa216a4854`)*
2. `.automation/DESKTOP_CAPABILITIES.md` *(tạo mới lúc `11:57:03+07:00`, SHA256: `1d38faded907cb4486d1aebfba895a1b08a145e966ff2a56789567aa631478e0`)*
3. `.automation/README.md` *(cập nhật lúc `11:57:03+07:00`, SHA256: `aad9d7556f66dbec06d34341f852b580af05d485a9ee842c277c4aa749119238`)*
4. `.automation/tests/desktop-policy.tests.ps1` *(tạo mới lúc `11:57:57+07:00`, SHA256: `f3a812c696d975ee277f5991c1195964164af78e59ad2f04f7f138c86ebc0b9d`)*

Trong suốt thời gian thực hiện `r1` (`12:03:42+07:00` → `12:07:30+07:00`), working tree hoàn toàn ổn định, không có bất kỳ thay đổi đồng thời nào.

---

## 2. Files Inspected & SHA256 Manifest

Tổng cộng **32 file** đã được kiểm tra trực tiếp (24 file quy tắc/tài liệu/automation/test trong manifest + 5 file state + 3 file Git metadata):

### A. Reviewed Snapshot Manifest (24 files — Aggregate SHA256: `081695e6be2d07660e7c059b0a249b50a2431ffb2fd12ece3c09c272cde3c8b4`)
| File Path | Status | SHA256 |
|---|---|---|
| `AGENTS.md` | Untracked | `704a7b8aa513981902a026af80cd776385941cad22df11acda946b788ddef755` |
| `DESKTOP_WORKFLOW.md` | Untracked (New in `r1`) | `54c904a560fd141f39b3fb1621f6b122deeeaf20de727a8dadee48fa216a4854` |
| `GEMINI_REVIEW.md` | Untracked | `f21983e008df77fe4498b0c21c3b0980938a3128d0764e6e81409f570aaa181c` |
| `README.md` | Tracked, Modified | `935f031d8de6525a82fb8399a97e3a702638587591af016eef47484427b24cac` |
| `.gitignore` | Untracked | `ada39342a93e4681e34d41e837fe96f4515182bd08abb70ea73eef50bac3eab5` |
| `.agents/agents/gemini-reviewer.md` | Untracked | `592564f0a8f640dc999f015443015d39ee18c780d2c89a9b6a2664337b38f8ed` |
| `.agents/skills/gemini-reviewer/SKILL.md` | Untracked | `2ff25ef52b1164040c9288de9c8309de86cd2a1a9645f6a3999920af1a730cb3` |
| `.automation/DESKTOP_CAPABILITIES.md` | Untracked (New in `r1`) | `1d38faded907cb4486d1aebfba895a1b08a145e966ff2a56789567aa631478e0` |
| `.automation/DESKTOP_ONLY` | Untracked | `920ef2baa7c409319f01b929be7c9ab106d2bd9fb1de99f62fc550091d73a0ab` |
| `.automation/README.md` | Untracked (Updated in `r1`) | `aad9d7556f66dbec06d34341f852b580af05d485a9ee842c277c4aa749119238` |
| `.automation/check-environment.ps1` | Untracked | `a4712e16ddf4e6b9208f83b78b94213c55bac29e8e3e519681b5ea96762f58f7` |
| `.automation/common.ps1` | Untracked | `53e27e6faf62737614377c41d066a849b310065a37060392b2b625d9f47c8415` |
| `.automation/config.json` | Untracked | `aa3f5b968510372aa882772f1049b0047041892320a91a8f41f676d138c6fece` |
| `.automation/controller.ps1` | Untracked | `42733eda449bc34af355fda3104412c5ca7bd27baad56aaa1192e43f60fd3d6b` |
| `.automation/fix.schema.json` | Untracked | `06d762d4abec5353ade11df180af6385232d30a8d327e2b402729099c6587628` |
| `.automation/install-hooks.ps1` | Untracked | `5e7775698e600de6c3878745b82313787ea114eb7398c3ad6a81d6e9f5d16238` |
| `.automation/invoke-codex.ps1` | Untracked | `0a429ba8a8a022c61baefb53def6bf0d45f063a99d77920e1da121c21382514b` |
| `.automation/invoke-gemini.ps1` | Untracked | `d929829ebcf28783c4f1a8f50cb3d814fa6d478a65b929468c96f80565852c09` |
| `.automation/orchestrator.ps1` | Untracked | `3d77e60ae8fc77d1f82277244de1922304219408240dd37e1af88e25e133755d` |
| `.automation/review.schema.json` | Untracked | `15d3a36a561d5d89cd9748b60b47a0f65e6cadda6022f3bb38e89bd7c103f926` |
| `.automation/reviewer-deny-tools.toml` | Untracked | `97310fe6edad9172f7553157c2d92db6b487c4f5bdb9ad509d7ff43c46f0bfd6` |
| `.automation/tests/desktop-policy.tests.ps1` | Untracked (New in `r1`) | `f3a812c696d975ee277f5991c1195964164af78e59ad2f04f7f138c86ebc0b9d` |
| `.automation/tests/run-tests.ps1` | Untracked (Unchanged) | `ae0258be73c872c56d36588d4ba472ef3120176447f5b56d667904cb0c17a371` |
| `.githooks/post-commit` | Untracked | `34b2f6e27f78c3b6e5a44d953725a9491cbf74a4b566652ac0087ac061d433df` |

### B. State, Report & Git Metadata Files Inspected
- `.agents/state/fixture-tests.json`, `.agents/state/live-probes.json`, `.agents/state/last-reviewed-commit.txt`, `.agents/state/review-lock.json`, `.agents/state/review-status.json` (tất cả được giữ nguyên vẹn, không bị ghi đè).
- `agentReport.md`, `reports/2026-11-04-89fb280812aa0643edb9fc6f3fcbd8998b2cc7d1-baseline-r0.md`, `reports/2026-11-04-89fb280812aa0643edb9fc6f3fcbd8998b2cc7d1-controller-prep.md`.
- `.git/HEAD`, `.git/refs/heads/tu`, `.git/config`.

---

## 3. Previous Findings Status (`r0` → `r1`)

| Finding ID | Severity | Status in `r1` | Verification Evidence |
|---|---|---|---|
| **`BASE-001`** | `HIGH` | **RESOLVED (`FIXED`)** | `DESKTOP_WORKFLOW.md` (55 dòng) và `.automation/DESKTOP_CAPABILITIES.md` (44 dòng) đã được tạo đầy đủ trên đĩa, khớp chính xác với mọi đường dẫn tham chiếu trong `AGENTS.md`, `GEMINI_REVIEW.md`, `README.md`, `.agents/agents/gemini-reviewer.md`, `.agents/skills/gemini-reviewer/SKILL.md` và `.automation/DESKTOP_ONLY`. Working tree không bị ghi đồng thời trong suốt phiên `r1`. |
| **`BASE-002`** | `MEDIUM` | **UNRESOLVED (`OPEN`)** | File `.automation/tests/run-tests.ps1` (SHA256 `ae0258be...`, sửa lần cuối `10:47:51+07:00`) hoàn toàn không thay đổi. Dù tài liệu mới giải thích không *chạy* `run-tests.ps1` khi bị cấm commit, bản thân code của `run-tests.ps1` (dòng 24–28 và 273–284) vẫn giữ lỗi logic: `New-Fixture` copy `.automation/DESKTOP_ONLY` vào repo fixture tạm khiến test case `'activation requires approval, real receipts and project tests'` bị dừng ở dòng 8 của `install-hooks.ps1` (`CLI_DISABLED_DESKTOP_ONLY`) thay vì kiểm tra được dòng 14–21 (`PRODUCT_OWNER_APPROVAL_REQUIRED`, `PROJECT_TEST_COMMANDS_MISSING`). Việc sửa file script `.automation/tests/run-tests.ps1` không tạo Git commit nên không vi phạm lệnh cấm commit. |
| **`BASE-003`** | `LOW` | **RESOLVED (`FIXED`)** | `.automation/README.md` (dòng 1–17) đã bổ sung mục `# Desktop-only: quy trình hiện hành`, giải thích rõ vai trò chốt khóa `.automation/DESKTOP_ONLY`, bài test `desktop-policy.tests.ps1`, và đóng khung phần tài liệu CLI cũ là `# Lưu trữ: Vận hành CLI code – review – fix (thử nghiệm, không hoạt động)`. |

---

## 4. Findings (Unresolved & New Findings in `r1`)

### Required Actions

### [BASE-002] [MEDIUM] (Unresolved from `r0`) Test case kiểm thử `install-hooks.ps1` trong `.automation/tests/run-tests.ps1` vẫn bị che khuất bởi `.automation/DESKTOP_ONLY`

- **Category:** Testing / Automation Regression
- **Confidence:** `0.98`
- **Confirmed:** `true`
- **Action:** `REQUIRED`
- **File:** `.automation/tests/run-tests.ps1`
- **Line:** `273`
- **Description:** Như đã chỉ ra ở `r0`, hàm `New-Fixture` (`.automation/tests/run-tests.ps1:24-28`) copy toàn bộ thư mục `.automation` (kể cả `.automation/DESKTOP_ONLY`) vào mỗi thư mục fixture tạm. Khi test case `'activation requires approval, real receipts and project tests'` (dòng 273–284) gọi `install-hooks.ps1 -Enable` và `install-hooks.ps1 -Enable -ProductOwnerApproved`, script dừng ngay tại dòng 8 của `install-hooks.ps1` (`if ($Enable) { Assert-TuCliAllowed $root }`) với lỗi `CLI_DISABLED_DESKTOP_ONLY`, không bao giờ chạm tới logic kiểm tra `-ProductOwnerApproved` (dòng 14) và `test_commands` (dòng 16). Vì dòng 279 và 281 chỉ kiểm tra `Check ($result.ExitCode -ne 0)`, test case này bị vô hiệu hóa ngầm.
- **Evidence:**
  - `.automation/tests/run-tests.ps1` giữ nguyên SHA256 `ae0258be73c872c56d36588d4ba472ef3120176447f5b56d667904cb0c17a371` từ `10:47:51+07:00`.
  - `.automation/install-hooks.ps1:8` gọi `Assert-TuCliAllowed $root` trước dòng 14 và 16.
- **Impact:** Bộ fixture suite được giữ lại (`AGENTS.md:30`: `.automation/ scripts, schemas, policies and fixture tests are retained`) mất khả năng kiểm thử các cổng an toàn của `install-hooks.ps1`.
- **Recommended Fix:** Trong `.automation/tests/run-tests.ps1` (dòng 273–284), kiểm tra riêng lỗi `CLI_DISABLED_DESKTOP_ONLY` khi có `.automation/DESKTOP_ONLY`, sau đó xóa `.automation/DESKTOP_ONLY` trong repo fixture tạm `$r` để kiểm tra tường minh `$result.Stderr -like '*PRODUCT_OWNER_APPROVAL_REQUIRED*'` và `'*PROJECT_TEST_COMMANDS_MISSING*'`. (Chỉ sửa code trong `run-tests.ps1`, không cần chạy suite nếu đang trong phiên cấm tạo commit tạm).
- **Verification:**
  - Đọc `.automation/tests/run-tests.ps1` dòng 273–284 xác nhận đã tách kiểm tra `DESKTOP_ONLY` và kiểm tra cụ thể mã lỗi trên `$result.Stderr`.

### [DESK-001] [MEDIUM] Bộ test chính sách mới `.automation/tests/desktop-policy.tests.ps1` vẫn PASS 100% ngay cả khi `.automation/DESKTOP_ONLY` bị xóa khỏi repository thật, và `Get-TuFingerprint` bỏ sót `DESKTOP_WORKFLOW.md`

- **Category:** Testing / Policy Verification
- **Confidence:** `1.0`
- **Confirmed:** `true`
- **Action:** `REQUIRED`
- **File:** `.automation/tests/desktop-policy.tests.ps1` (và `.automation/common.ps1`)
- **Line:** `53`
- **Description:**
  1. Trong `.automation/tests/desktop-policy.tests.ps1`, bài kiểm tra duy nhất chạy trên repository thật (`$projectRoot`) là dòng 53: `Assert-DesktopCheck (-not (Test-TuEnabled $projectRoot)) 'The actual repository must remain disabled.'`. Tuy nhiên, hàm `Test-TuEnabled` (`.automation/common.ps1:178-185`) trả về `$false` nếu không có `.agents/state/activation.json`. Vì `$projectRoot` vốn không có `.agents/state/activation.json`, `Test-TuEnabled $projectRoot` **luôn trả về `$false` kể cả khi `.automation/DESKTOP_ONLY` bị xóa khỏi `$projectRoot`**.
  2. Toàn bộ 4 bài kiểm tra còn lại (dòng 55, 57, 59, 61: `Test-TuEnabled`, `Assert-TuCliAllowed`, `Invoke-TuCodexText`, `Invoke-TuGeminiText`) đều chỉ kiểm tra trên thư mục tạm `$fixtureRoot` — nơi dòng 48 vừa tự tạo file `Write-TuUtf8 (Join-Path $fixtureRoot '.automation/DESKTOP_ONLY')`.
  3. Ngoài ra, hàm `Get-TuFingerprint` (`.automation/common.ps1:142`) hiện chỉ băm `@('AGENTS.md','GEMINI_REVIEW.md','.gitignore')` ở thư mục gốc mà quên bổ sung `'DESKTOP_WORKFLOW.md'` (tài liệu quy trình bắt buộc mới được thêm).
- **Evidence:**
  - `.automation/tests/desktop-policy.tests.ps1:48`: Tự tạo `$fixtureRoot/.automation/DESKTOP_ONLY`.
  - `.automation/tests/desktop-policy.tests.ps1:53`: Chỉ gọi `Test-TuEnabled $projectRoot`, không gọi `Assert-TuCliAllowed $projectRoot`, `Invoke-TuCodexText $projectRoot`, hay `Invoke-TuGeminiText $projectRoot`.
  - `.automation/common.ps1:180-181`: `if (-not (Test-Path -LiteralPath $path)) { return $false }` (với `$path = Join-Path $Root '.agents/state/activation.json'`).
  - `.automation/common.ps1:142`: `$paths = @('AGENTS.md','GEMINI_REVIEW.md','.gitignore')` — thiếu `'DESKTOP_WORKFLOW.md'`.
- **Impact:** Nếu file `.automation/DESKTOP_ONLY` trong repository thật bị xóa nhầm, lệnh `powershell -NoProfile -File .automation/tests/desktop-policy.tests.ps1` vẫn báo `Desktop policy checks passed: 5` (false positive), không phát hiện được việc chốt khóa CLI của repo đã mất.
- **Recommended Fix:**
  1. Trong `.automation/tests/desktop-policy.tests.ps1`, thêm các kiểm tra trực tiếp trên `$projectRoot`:
     - `Assert-DesktopCheck (Test-Path -LiteralPath (Join-Path $projectRoot '.automation/DESKTOP_ONLY')) 'Missing .automation/DESKTOP_ONLY in repository.'`
     - `Assert-DesktopBlocked { Assert-TuCliAllowed $projectRoot }`
     - `Assert-DesktopBlocked { Invoke-TuCodexText $projectRoot $null 'Never sent to a client' }`
     - `Assert-DesktopBlocked { Invoke-TuGeminiText $projectRoot $null 'Never sent to a client' }`
  2. Thêm kiểm tra đối chứng (negative test) trên `$fixtureRoot` sau khi xóa `$fixtureRoot/.automation/DESKTOP_ONLY` để chứng minh `Assert-TuCliAllowed` và `Test-TuEnabled` thực sự thay đổi hành vi nhờ file `.automation/DESKTOP_ONLY`.
  3. Trong `.automation/common.ps1:142`, thêm `'DESKTOP_WORKFLOW.md'` vào danh sách `$paths` của `Get-TuFingerprint` (nếu file tồn tại).
- **Verification:**
  - Kiểm tra `.automation/tests/desktop-policy.tests.ps1` xác nhận có gọi `Assert-TuCliAllowed $projectRoot`, `Invoke-TuCodexText $projectRoot`, `Invoke-TuGeminiText $projectRoot` và kiểm tra negative case.
  - Kiểm tra `.automation/common.ps1:142` xác nhận `Get-TuFingerprint` bao gồm `DESKTOP_WORKFLOW.md`.

### [DESK-002] [MEDIUM] Thiếu gói handoff/disposition thực tế (`reports/<session>/handoff-r1.md`, `fix-response-r1.md`) và mâu thuẫn giữa yêu cầu xác minh SHA256/untracked files với quy tắc cấm chạy lệnh trong `DESKTOP_WORKFLOW.md` / `GEMINI_REVIEW.md`

- **Category:** Workflow Integrity / Handoff Verification
- **Confidence:** `0.95`
- **Confirmed:** `true`
- **Action:** `REQUIRED`
- **File:** `DESKTOP_WORKFLOW.md` (dòng 9, 17, 25, 37) và `GEMINI_REVIEW.md` (dòng 7, 9, 13)
- **Line:** `17`
- **Description:**
  1. **Quy trình bàn giao vừa viết chưa được áp dụng cho chính vòng `r1`:** `AGENTS.md` (dòng 22–23), `GEMINI_REVIEW.md` (dòng 7, 13) và `DESKTOP_WORKFLOW.md` (dòng 17, 37) yêu cầu Codex phải ghi disposition (`FIXED`/`REJECTED` kèm lý do cho `BASE-001`, `BASE-002`, `BASE-003`) vào `reports/<session>/fix-response-r1.md` và tạo `reports/<session>/handoff-r1.md`, `diff-r1.patch`, `tests-r1.md` kèm bảng SHA256 manifest. Tuy nhiên, thư mục `reports/` hiện hoàn toàn không có thư mục con `<session>` hay các file handoff/disposition này.
  2. **Mâu thuẫn kỹ thuật trong quy trình xác minh SHA256 & untracked files:**
     - `GEMINI_REVIEW.md` (dòng 7) và `DESKTOP_WORKFLOW.md` (dòng 25) yêu cầu Gemini Reviewer kiểm tra SHA256 manifest, xác minh source không bị thay đổi trong lúc review, và kết thúc báo cáo bằng manifest đã review.
     - Nhưng `GEMINI_REVIEW.md` (dòng 9) và `DESKTOP_WORKFLOW.md` (dòng 9, 25) lại yêu cầu khóa hoàn toàn `command(*)` (`chặn terminal command(*)`, `Use file-reading tools and the prepared diff; do not run terminal commands`). Công cụ `read_file` của Antigravity Desktop chỉ trả về nội dung văn bản theo dòng (tối đa 800 dòng / 46.080 bytes), **không thể tính mã băm SHA256** của file gốc trên đĩa (đặc biệt khi có khác biệt CRLF/LF như cảnh báo trên `README.md`) và không thể tự đối chiếu SHA256 trước/sau khi review nếu không có lệnh đọc hash hoặc script hỗ trợ.
     - Hơn nữa, `DESKTOP_WORKFLOW.md` (dòng 17) yêu cầu tạo `diff-r0.patch`, nhưng lệnh `git diff` tiêu chuẩn không xuất nội dung của các file untracked (hiện chiếm 23/24 file của repo), và khi sửa trực tiếp trên dirty worktree từ `r0` sang `r1` mà không commit, nội dung cũ ở `r0` của các file untracked bị ghi đè tại chỗ, không còn lưu trong Git object database.
- **Evidence:**
  - Kiểm tra thư mục `f:\MMRPG PNTT\reports` chỉ có `.gitkeep`, `2026-11-04-89fb280812aa0643edb9fc6f3fcbd8998b2cc7d1-baseline-r0.md` và `2026-11-04-89fb280812aa0643edb9fc6f3fcbd8998b2cc7d1-controller-prep.md`.
  - `DESKTOP_WORKFLOW.md:9`: `chặn terminal command(*)` so với `DESKTOP_WORKFLOW.md:25` và `GEMINI_REVIEW.md:7`: yêu cầu kiểm tra SHA256 manifest và phát hiện source drift trong lúc review.
- **Impact:**
  - Nếu người dùng khóa `command(*)` trong Antigravity Desktop theo hướng dẫn, Gemini không có phương tiện kỹ thuật để tự tính lại SHA256 nhằm phát hiện file bị sửa trong lúc review hoặc phát hiện file untracked bị bỏ sót khỏi handoff.
  - Thiếu `fix-response-r1.md` và `handoff-r1.md` làm mất hồ sơ disposition chính thức của developer ở vòng `r1`.
- **Recommended Fix:**
  1. Tạo bổ sung gói handoff/disposition chuẩn dưới `reports/<session>/` (gồm `fix-response-r1.md` cho `r1` và `fix-response-r2.md` / `handoff-r2.md` khi bàn giao vòng tiếp theo).
  2. Chuẩn hóa quy tắc tính SHA256 manifest trong `DESKTOP_WORKFLOW.md` (ví dụ cung cấp một hàm/script chỉ đọc tạo manifest SHA256 theo thứ tự đường dẫn chuẩn hóa) và nêu rõ trong `DESKTOP_WORKFLOW.md` / `GEMINI_REVIEW.md`: khi `command(*)` bị tắt trong Antigravity, việc xác minh lại SHA256 manifest trước và sau khi Gemini đọc file do người dùng/Codex thực hiện bằng script kiểm tra trên máy, còn Gemini đối chiếu nội dung văn bản đọc qua `read_file` với danh sách file trong `handoff-rX.md`.
- **Verification:**
  - Kiểm tra sự tồn tại của `reports/<session>/handoff-r2.md` và `reports/<session>/fix-response-r2.md` trong lần bàn giao kế tiếp.
  - Kiểm tra `DESKTOP_WORKFLOW.md` và `GEMINI_REVIEW.md` đã làm rõ cơ chế kiểm chứng SHA256 khi `command(*)` bị khóa.

---

### Optional Improvements

### [DESK-003] [LOW] Quy ước đặt tên file báo cáo lịch sử chưa đồng nhất giữa tài liệu quy trình và nguy cơ trùng tên khi làm việc trên dirty worktree

- **Category:** Report Archiving / Traceability
- **Confidence:** `0.90`
- **Confirmed:** `true`
- **Action:** `OPTIONAL`
- **File:** `DESKTOP_WORKFLOW.md` (dòng 25, 41) và `GEMINI_REVIEW.md` (dòng 11)
- **Line:** `25`
- **Description:** `GEMINI_REVIEW.md:11` và `DESKTOP_WORKFLOW.md:25` quy định mẫu tên file lịch sử là `reports/YYYY-MM-DD-<HEAD>-<session>-r0.md`, trong khi prompt vòng `r1` yêu cầu `reports/2026-11-04-<reviewed-sha>-desktop-r1.md`. Khi repo chưa tạo commit mới, `<HEAD>` luôn cố định là `89fb280812aa0643edb9fc6f3fcbd8998b2cc7d1` (commit rỗng ban đầu). Nếu tên file lịch sử không chứa `<session>` hoặc `<manifest8>` (8 ký tự đầu của SHA256 manifest), hai phiên review khác nhau trong cùng một ngày trên cùng `HEAD` sẽ trùng tên file.
- **Evidence:**
  - `DESKTOP_WORKFLOW.md:25`: `reports/YYYY-MM-DD-<HEAD>-<session>-r0.md`.
  - `HEAD` hiện tại (`89fb280812aa0643edb9fc6f3fcbd8998b2cc7d1`) chỉ chứa `README.md` 0 byte nhưng đứng tên cho mọi báo cáo dirty worktree.
- **Impact:** Có nguy cơ trùng tên file trong `reports/` nếu mở phiên review thứ hai trong ngày mà không gắn `<session>` hoặc `<manifest8>`, và dễ gây nhầm lẫn rằng commit `89fb280...` đã bao gồm các file untracked.
- **Recommended Fix:** Thống nhất quy ước tên file lịch sử trong `DESKTOP_WORKFLOW.md` và `GEMINI_REVIEW.md` có kèm định danh phiên/manifest, và quy định rõ khi gọi `write_file` vào `reports/` phải luôn đặt `Overwrite: false`.
- **Verification:**
  - Kiểm tra `DESKTOP_WORKFLOW.md` và `GEMINI_REVIEW.md` quy định nhất quán mẫu tên file lịch sử và cờ `Overwrite: false`.

---

## 5. Desktop Workflow Correctness Assessment (Scope 1.A & 1.B)

- **Tính đầy đủ & trung thực của tài liệu (`DESKTOP_WORKFLOW.md`, `.automation/DESKTOP_CAPABILITIES.md`, `README.md`, `.automation/README.md`):**
  - Tài liệu đã tách bạch rất rõ ràng và trung thực giữa: (1) bằng chứng thực tế trên máy (`Antigravity.exe` `2.28.2`, extension `openai.chatgpt` `26.1021.22027`, trạng thái Git repo), (2) tính năng được tài liệu chính thức của OpenAI và Google mô tả, và (3) những tính năng chưa được kiểm chứng hoặc không được cấu hình (như bridge tự động giữa hai Desktop app).
  - Tuyệt đối không có tuyên bố sai sự thật nào về việc tồn tại cầu nối tự động giữa Codex Desktop và Antigravity Desktop.
- **Tính nhất quán của các quy tắc Reviewer (`AGENTS.md`, `GEMINI_REVIEW.md`, `.agents/agents/gemini-reviewer.md`, `.agents/skills/gemini-reviewer/SKILL.md`):**
  - Cả 4 file đều thống nhất: model bắt buộc là `gemini-4-argon`, chỉ làm việc trên nhánh `tu`, giới hạn tối đa 3 lượt sửa (`r0` → `r1..r3`), dừng ở `CRITICAL` để Product Owner quyết định, không tự ý bỏ qua `HIGH`, chỉ ghi `agentReport.md` và `reports/`, không gọi CLI AI hay tái sử dụng thông tin xác thực của Desktop.
  - Điểm duy nhất cần chỉnh sửa trong quy trình là giải quyết `[DESK-002]` (áp dụng thực tế gói handoff `reports/<session>/...` và tháo gỡ mâu thuẫn giữa yêu cầu xác minh SHA256 với việc khóa `command(*)`).

---

## 6. CLI-Disable Policy Verification (Scope 1.C)

Kiểm tra tĩnh toàn bộ chuỗi script trong `.automation/` và `.githooks/post-commit` xác nhận:
1. **`.automation/DESKTOP_ONLY`:** Tồn tại tại đường dẫn chuẩn và được kiểm tra trực tiếp bởi `Assert-TuCliAllowed` (`.automation/common.ps1:172-176`) và `Test-TuEnabled` (`.automation/common.ps1:178-185`).
2. **`.automation/invoke-codex.ps1` (dòng 5) & `.automation/invoke-gemini.ps1` (dòng 61):** Đều gọi `Assert-TuCliAllowed $Root` ở dòng đầu tiên của hàm `Invoke-TuCodexText` và `Invoke-TuGeminiText`, chặn đứng **trước khi** phân giải đường dẫn CLI (`Resolve-TuApplication 'codex'`, `Resolve-TuGemini`), trước khi đọc `.gemini/settings.json` hay `oauth_creds.json`, và trước khi tạo thư mục tạm hay gọi tiến trình con.
3. **`.automation/check-environment.ps1` (dòng 5):** Gọi `Assert-TuCliAllowed $root` ngay ở dòng 5, chặn cả lệnh kiểm tra thông thường lẫn `-Probe`.
4. **`.automation/install-hooks.ps1` (dòng 8):** Gọi `if ($Enable) { Assert-TuCliAllowed $root }` ngay ở đầu script, chặn việc cài đặt `core.hooksPath=.githooks` và kích hoạt automation.
5. **`.automation/controller.ps1` (dòng 88) & `.automation/orchestrator.ps1`:** Trong chế độ chạy thật (`-not $Fixture`), `Invoke-TuReview` kiểm tra `if (-not $Fixture -and -not (Test-TuEnabled $Root)) { return [pscustomobject]@{ status='DISABLED'; commit_sha=$commit } }`. Vì `Test-TuEnabled` trả về `$false` ngay dòng đầu tiên khi có `.automation/DESKTOP_ONLY` (bất kể có file `.agents/state/activation.json` cũ hay không), mọi lệnh gọi `orchestrator.ps1` (kể cả `-Resume` hoặc gọi từ `.githooks/post-commit`) đều trả về `DISABLED` mà không chạm tới AI adapter.
6. **`.githooks/post-commit` & `.git/config`:** Kiểm tra `.git/config` xác nhận **không** có `core.hooksPath` nào được cài đặt; kể cả khi gọi trực tiếp `.githooks/post-commit`, nó sẽ gọi `orchestrator.ps1 -FromHook` và nhận kết quả `DISABLED`.

---

## 7. Policy Test Verification (Scope 1.D)

Đánh giá độc lập 5 bài kiểm tra trong `.automation/tests/desktop-policy.tests.ps1`:
- **Điểm tốt:**
  - Đặt bẫy (tripwires) ghi đè `Resolve-TuApplication`, `Resolve-TuGemini`, `Invoke-TuProcess` (dòng 10–12) để đảm bảo không có bất kỳ tiến trình CLI hay lệnh Git nào bị gọi ngầm.
  - Kiểm tra bảo toàn mã băm SHA256 của toàn bộ `.agents/state/*`, `reports/*`, `agentReport.md`, `.git/HEAD`, `.git/index`, `.git/config` trước và sau khi chạy test (dòng 26–43, 64).
  - Dọn dẹp thư mục tạm an toàn, không dùng `Remove-Item -Recurse` mù quáng (dòng 67–79).
- **Lỗ hổng đã xác nhận (`[DESK-001]` & `[BASE-002]`):**
  - 4/5 bài kiểm tra trong `desktop-policy.tests.ps1` chạy trên `$fixtureRoot` (nơi test tự tạo `.automation/DESKTOP_ONLY` ở dòng 48) thay vì `$projectRoot`, và bài kiểm tra duy nhất chạy trên `$projectRoot` (dòng 53: `Test-TuEnabled $projectRoot`) vẫn trả về `$false` nhờ việc không có `activation.json`. Do đó, nếu xóa `.automation/DESKTOP_ONLY` khỏi repo thật, cả 5 bài test vẫn PASS.
  - Chưa sửa lỗi che khuất test trong `.automation/tests/run-tests.ps1` (`[BASE-002]`).

---

## 8. Remaining Security and Integrity Risks (Scope 1.E)

1. **Rủi ro thiếu khóa đồng bộ giữa hai ứng dụng Desktop trên cùng working tree:**
   - Khi mở chung thư mục `f:\MMRPG PNTT` ở chế độ Local trên cả Codex Desktop và Antigravity Desktop, việc ngăn chặn ghi đồng thời hoàn toàn phụ thuộc vào kỷ luật thao tác của người dùng (chờ một bên hoàn tất rồi mới bấm sang bên kia).
2. **Rủi ro mất lịch sử trung gian của các file untracked trên dirty worktree:**
   - Hiện tại 23/24 file quy tắc/automation đang là untracked và `HEAD` vẫn là commit rỗng `89fb280812aa0643edb9fc6f3fcbd8998b2cc7d1`. Nếu các vòng sửa lỗi tiếp theo sửa đè lên các file untracked mà không có bản lưu diff đầy đủ (vì `git diff` bỏ qua untracked files) hoặc chưa được Product Owner cho phép commit mốc baseline, nội dung của vòng trước sẽ bị ghi đè trực tiếp trên đĩa.
3. **Rủi ro quyền ghi trong IDE Desktop:**
   - Như `.automation/DESKTOP_CAPABILITIES.md` (dòng 24–26) đã ghi nhận trung thực, quyền chỉ ghi `agentReport.md` và `reports/` trong Antigravity Desktop cần được người dùng cấu hình/kiểm duyệt trên UI (`Ask write_file(*)`, `Deny command(*)`), không được tự động cưỡng chế bởi `.automation/reviewer-deny-tools.toml`.

---

## 9. Final Verdict

- **Verdict (Desktop Workflow Migration `r1`):** **`CHANGES_REQUIRED`**
  - **Resolved from `r0`:** `BASE-001` (`HIGH`), `BASE-003` (`LOW`).
  - **Remaining Required Actions (3 `MEDIUM`):** `BASE-002` (chưa sửa trong `.automation/tests/run-tests.ps1`), `DESK-001` (lỗ hổng kiểm thử `$projectRoot` trong `.automation/tests/desktop-policy.tests.ps1` và thiếu `DESKTOP_WORKFLOW.md` trong `Get-TuFingerprint`), `DESK-002` (thiếu gói handoff/disposition `reports/<session>/...` thực tế và mâu thuẫn xác minh SHA256 khi khóa `command(*)`).
  - **Optional Improvements (1 `LOW`):** `DESK-003` (chuẩn hóa tên file lịch sử kèm định danh phiên/manifest và cờ `Overwrite: false`).
- **Verdict (Overall Tu Tiên Online Game Application):** **`BLOCKED` (`NOT_EVALUATED`)** — Repository hiện chưa có mã nguồn ứng dụng game (`frontend/`, `backend/`, `tests/`) và chưa có database migrations/RLS (`supabase/migrations/`).
