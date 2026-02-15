/**
 * Crop tool — draw a crop rectangle and apply to store.
 */
import { useAnnotationStore } from "../useAnnotationStore";
import type { Point, Rect, ToolHandler } from "../types";
import { normalizeRect } from "../types";

let start: Point | null = null;

export const cropTool: ToolHandler = {
  onMouseDown(pos) {
    start = pos;
    useAnnotationStore.getState().setCropRect({ x: pos.x, y: pos.y, width: 0, height: 0 });
  },

  onMouseMove(pos) {
    if (!start) return;
    const rect: Rect = {
      x: start.x,
      y: start.y,
      width: pos.x - start.x,
      height: pos.y - start.y,
    };
    useAnnotationStore.getState().setCropRect(normalizeRect(rect));
  },

  onMouseUp() {
    if (!start) return;
    const state = useAnnotationStore.getState();
    const crop = state.cropRect;
    if (crop && crop.width > 5 && crop.height > 5) {
      state.confirmCrop();
    } else {
      state.setCropRect(null);
    }
    start = null;
  },

  cursor: "crosshair",
};
