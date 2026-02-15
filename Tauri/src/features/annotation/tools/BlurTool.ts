/**
 * Blur region tool.
 * Draws a rectangle that is rendered with a Konva blur filter.
 */
import { useAnnotationStore } from "../useAnnotationStore";
import type { Annotation, Point, ToolHandler } from "../types";
import { createAnnotation, normalizeRect } from "../types";

let start: Point | null = null;
let current: Annotation | null = null;

export const blurTool: ToolHandler = {
  onMouseDown(pos) {
    const state = useAnnotationStore.getState();
    start = pos;
    current = createAnnotation(
      "blur",
      { x: pos.x, y: pos.y, width: 0, height: 0 },
      "transparent",
      0,
      state.annotations.length + 1,
      { blurRadius: state.blurRadius },
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
      if (rect.width < 5 && rect.height < 5) {
        useAnnotationStore.getState().deleteAnnotation(current.id);
      }
    }
    start = null;
    current = null;
  },

  cursor: "crosshair",
};
