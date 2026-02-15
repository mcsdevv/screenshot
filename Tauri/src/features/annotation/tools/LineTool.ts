/**
 * Line annotation tool.
 * Encodes start as rect origin, direction as rect width/height (can be negative).
 * Shift constrains to horizontal/vertical.
 */
import { useAnnotationStore } from "../useAnnotationStore";
import type { Annotation, Point, ToolHandler } from "../types";
import { constrainToAxis, createAnnotation } from "../types";

let start: Point | null = null;
let current: Annotation | null = null;

export const lineTool: ToolHandler = {
  onMouseDown(pos) {
    const state = useAnnotationStore.getState();
    start = pos;
    current = createAnnotation(
      "line",
      { x: pos.x, y: pos.y, width: 0, height: 0 },
      state.currentColor,
      state.currentStrokeWidth,
      state.annotations.length + 1,
    );
    state.addAnnotation(current);
  },

  onMouseMove(pos, shiftKey) {
    if (!start || !current) return;
    const end = shiftKey ? constrainToAxis(start, pos) : pos;
    useAnnotationStore.getState().updateAnnotation({
      ...current,
      rect: {
        x: start.x,
        y: start.y,
        width: end.x - start.x,
        height: end.y - start.y,
      },
    });
  },

  onMouseUp() {
    if (current) {
      const { width, height } = current.rect;
      if (Math.abs(width) < 3 && Math.abs(height) < 3) {
        useAnnotationStore.getState().deleteAnnotation(current.id);
      }
    }
    start = null;
    current = null;
  },

  cursor: "crosshair",
};
