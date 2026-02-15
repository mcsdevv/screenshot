/**
 * Select/move tool — hit-test annotations, drag to reposition.
 */
import { useAnnotationStore } from "../useAnnotationStore";
import type { Annotation, Point, Rect, ToolHandler } from "../types";

/** Slop radius for hit-testing (pixels in image space). */
const HIT_SLOP = 8;

let dragAnchor: Point | null = null;
let dragAnnotation: Annotation | null = null;
let originalRect: Rect | null = null;
let originalPoints: Point[] | null = null;

function hitTest(pos: Point, annotations: Annotation[], hidden: Set<string>): Annotation | null {
  // Iterate in reverse so topmost annotation wins.
  for (let i = annotations.length - 1; i >= 0; i--) {
    const a = annotations[i];
    if (hidden.has(a.id) || !a.isVisible) continue;

    switch (a.type) {
      case "line":
      case "arrow": {
        const start: Point = { x: a.rect.x, y: a.rect.y };
        const end: Point = { x: a.rect.x + a.rect.width, y: a.rect.y + a.rect.height };
        if (distToSegment(pos, start, end) <= Math.max(HIT_SLOP, a.strokeWidth / 2)) return a;
        break;
      }
      case "pencil":
      case "highlighter": {
        const tolerance = Math.max(HIT_SLOP, (a.type === "highlighter" ? a.strokeWidth * 3 : a.strokeWidth) / 2);
        for (let j = 0; j < a.points.length - 1; j++) {
          if (distToSegment(pos, a.points[j], a.points[j + 1]) <= tolerance) return a;
        }
        if (a.points.length === 1 && dist(pos, a.points[0]) <= tolerance) return a;
        break;
      }
      default: {
        const r = a.rect;
        if (
          pos.x >= r.x - HIT_SLOP &&
          pos.x <= r.x + r.width + HIT_SLOP &&
          pos.y >= r.y - HIT_SLOP &&
          pos.y <= r.y + r.height + HIT_SLOP
        ) {
          return a;
        }
      }
    }
  }
  return null;
}

function dist(a: Point, b: Point): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function distToSegment(p: Point, s: Point, e: Point): number {
  const dx = e.x - s.x;
  const dy = e.y - s.y;
  const lenSq = dx * dx + dy * dy;
  if (lenSq === 0) return dist(p, s);
  const t = Math.max(0, Math.min(1, ((p.x - s.x) * dx + (p.y - s.y) * dy) / lenSq));
  return dist(p, { x: s.x + t * dx, y: s.y + t * dy });
}

export const selectTool: ToolHandler = {
  onMouseDown(pos) {
    const state = useAnnotationStore.getState();
    const hit = hitTest(pos, state.annotations, state.hiddenAnnotationIds);

    if (hit) {
      state.selectAnnotation(hit.id);
      dragAnchor = pos;
      dragAnnotation = hit;
      originalRect = { ...hit.rect };
      originalPoints = hit.points.map((p) => ({ ...p }));
    } else {
      state.selectAnnotation(null);
      dragAnchor = null;
      dragAnnotation = null;
    }
  },

  onMouseMove(pos) {
    if (!dragAnchor || !dragAnnotation || !originalRect) return;
    const dx = pos.x - dragAnchor.x;
    const dy = pos.y - dragAnchor.y;

    const updated: Annotation = {
      ...dragAnnotation,
      rect: {
        ...originalRect,
        x: originalRect.x + dx,
        y: originalRect.y + dy,
      },
      points: originalPoints
        ? originalPoints.map((p) => ({ x: p.x + dx, y: p.y + dy }))
        : dragAnnotation.points,
    };
    useAnnotationStore.getState().updateAnnotation(updated);
  },

  onMouseUp() {
    dragAnchor = null;
    dragAnnotation = null;
    originalRect = null;
    originalPoints = null;
  },

  cursor: "default",
};
