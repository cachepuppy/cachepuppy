import type { Metadata } from "next";
import type { ReactNode } from "react";
import { SessionProvider } from "@/context/SessionContext";
import "./globals.css";

export const metadata: Metadata = {
  title: "CachePuppy demo",
  description:
    "Single Next.js app showcasing CachePuppy caching, realtime, and workflows.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-[var(--color-bg)] text-[var(--color-fg)]">
        <SessionProvider>{children}</SessionProvider>
      </body>
    </html>
  );
}
