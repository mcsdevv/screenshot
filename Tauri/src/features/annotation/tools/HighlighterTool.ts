/**
 * Highlighter tool — semi-transparent freehand stroke.
 * Same mechanics as PencilTool but thicker stroke, 30% opacity,
 * and "highlighter" annotation type.
 */
import { useAnnotationStore } from "../useAnnotationStore";
import type { Annotation, Point, ToolHandler } from "../types";
import { createAnnotation } from "../types";

const MIN_POINT_DISTANCE = 2;
const HIGHLIGHTER_OPACITY = 0.3;
const HIGHLIGHTER_WIDTH_MULTIPLIER = 3;

let current: Annotation | null = null;
let points: Point[] = [];

/**
 * Convert a hex color to an rgba() string with the given alpha.
 * Falls through to raw value + opacity annotation property for Konva rendering.
 */
function withOpacity(hex: string, alpha: number): string {
  // Strip leading #
  const raw = hex.replace("#", "");
  const r = parseInt(raw.substring(0, 2), 16);
  const g = parseInt(raw.substring(2, 4), 16);
  const b = parseInt(raw.substring(4, 6), 16);
  if (Number.isNaN(r) || Number.isNaN(g) || Number.isNaN(b)) return hex;
  return `rgba(${r},${g},${b},${alpha})`;
}

export const highlighterTool: ToolHandler = {
  onMouseDown(pos) {
    const state = useAnnotationStore.getState();
    points = [pos];
    current = createAnnotation(
      "highlighter",
      { x: pos.x, y: pos.y, width: 0, height: 0 },
      withOpacity(state.currentColor, HIGHLIGHTER_OPACITY),
      state.currentStrokeWidth * HIGHLIGHTER_WIDTH_MULTIPLIER,
      state.annotations.length + 1,
      { points: [pos] },
    );
    state.addAnnotation(current);
  },

  onMouseMove(pos) {
    if (!current) return;
    const last = points[points.length - 1];
    if (Math.hypot(pos.x - last.x, pos.y - last.y) < MIN_POINT_DISTANCE) return;
    points.push(pos);
    useAnnotationStore.getState().updateAnnotation({ ...current, points: [...points] });
  },

  onMouseUp() {
    if (current && points.length < 2) {
      useAnnotationStore.getState().deleteAnnotation(current.id);
    }
    current = null;
    points = [];
  },

  cursor: "crosshair",
};
