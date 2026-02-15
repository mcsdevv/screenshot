/**
 * Ellipse/circle annotation tool.
 * Stored as a rect bounding box; Konva renders as Ellipse from the rect.
 */
import { useAnnotationStore } from "../useAnnotationStore";
import type { Annotation, Point, ToolHandler } from "../types";
import { createAnnotation, normalizeRect } from "../types";

let start: Point | null = null;
let current: Annotation | null = null;

export const circleTool: ToolHandler = {
  onMouseDown(pos) {
    const state = useAnnotationStore.getState();
    start = pos;
    current = createAnnotation(
      "circleOutline",
      { x: pos.x, y: pos.y, width: 0, height: 0 },
      state.currentColor,
      state.currentStrokeWidth,
      state.annotations.length + 1,
    );
    state.addAnnotation(current);
  },

  onMouseMove(pos) {
    if (!start || !current) return;
    const rect = normalizeRect({
      x: start.x,
      y: start.y,
      width: pos.x - start.x,
      height: pos.y - start.y,
    });
    useAnnotationStore.getState().updateAnnotation({ ...current, rect });
  },

  onMouseUp() {
    if (current) {
      const rect = current.rect;
      if (rect.width < 3 && rect.height < 3) {
        useAnnotationStore.getState().deleteAnnotation(current.id);
      }
    }
    start = null;
    current = null;
  },

  cursor: "crosshair",
};
