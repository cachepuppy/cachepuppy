import { clamp01 } from "./cursors";

export function attachBoardCursorTracking(
  el: HTMLElement,
  options: {
    isActive: () => boolean;
    publish: (xPct: number, yPct: number) => void;
  },
): () => void {
  const { isActive, publish } = options;
  const last = { xPct: 0, yPct: 0 };
  let rafId = 0;
  let scheduled = false;

  const flushMove = () => {
    scheduled = false;
    rafId = 0;
    if (!isActive()) {
      return;
    }
    publish(last.xPct, last.yPct);
  };

  const onMove = (e: MouseEvent) => {
    if (!isActive()) {
      return;
    }
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) {
      return;
    }
    last.xPct = clamp01((e.clientX - r.left) / r.width);
    last.yPct = clamp01((e.clientY - r.top) / r.height);
    if (!scheduled) {
      scheduled = true;
      rafId = requestAnimationFrame(flushMove);
    }
  };

  const onLeaveBoard = () => {
    if (rafId !== 0) {
      cancelAnimationFrame(rafId);
      rafId = 0;
      scheduled = false;
    }
  };

  el.addEventListener("mousemove", onMove);
  el.addEventListener("mouseleave", onLeaveBoard);

  return () => {
    onLeaveBoard();
    el.removeEventListener("mousemove", onMove);
    el.removeEventListener("mouseleave", onLeaveBoard);
  };
}
