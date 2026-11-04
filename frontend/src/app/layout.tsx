import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Tu Tiên Online — Đài thử luyện",
  description: "M1 local game foundation. Server-authoritative sandbox.",
};
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="vi">
      <body>{children}</body>
    </html>
  );
}
