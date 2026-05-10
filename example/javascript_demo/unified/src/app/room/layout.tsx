import type { ReactNode } from "react";
import { RoomShell } from "@/components/RoomShell";

export default function RoomLayout({ children }: { children: ReactNode }) {
  return <RoomShell>{children}</RoomShell>;
}
