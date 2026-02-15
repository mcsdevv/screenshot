/**
 * Freehand pencil tool.
 * Collects points into a polyline annotation. Points are throttled by
 * minimum distance to avoid excessive density.
 */
import { useAnnotationStore } from "../useAnnotationStore";
import type { Annotation, Point, ToolHandler } from "../types";
import { createAnnotation } from "../types";

/** Minimum distance between consecutive points (px in image coords). */
const MIN_POINT_DISTANCE = 2;

let current: Annotation | null = null;
let points: Point[] = [];

export const pencilTool: ToolHandler = {
  onMouseDown(pos) {
    const state = useAnnotationStore.getState();
    points = [pos];
    current = createAnnotation(
      "pencil",
      { x: pos.x, y: pos.y, width: 0, height: 0 },
      state.currentColor,
      state.currentStrokeWidth,
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
