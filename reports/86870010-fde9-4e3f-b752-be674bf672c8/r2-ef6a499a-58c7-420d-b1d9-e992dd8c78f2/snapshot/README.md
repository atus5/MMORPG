# Tu Tiên Online

Repository đang ở giai đoạn chuẩn bị, chưa có ứng dụng game hoặc migration database.

Quy trình hiện tại dùng **Codex Desktop trên Windows** để code/test và **Antigravity Desktop với Gemini 4 Argon** để review độc lập. Đọc [DESKTOP_WORKFLOW.md](DESKTOP_WORKFLOW.md) để bàn giao, nhận findings và review lại tối đa ba lượt sửa. Người dùng tự thực hiện merge cuối cùng; hai AI không merge vào `main`.

Các thành phần CLI cũ tại [`.automation/`](.automation/README.md) được giữ lại dưới dạng thử nghiệm và bị tắt bằng `.automation/DESKTOP_ONLY`. Không cần vận hành hoặc xác thực Codex/Gemini CLI. Lịch sử report/state vẫn được bảo toàn; không có cầu nối Desktop tự động nào được kích hoạt.

Đọc [AGENTS.md](AGENTS.md) trước khi phát triển. Supabase project ref: `neealjejigkokldujhti`; không tự triển khai database production.
