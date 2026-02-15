/**
 * Text annotation tool.
 * Click places a text annotation; actual editing is handled by the Konva
 * text component (double-click to edit). mouseMove/mouseUp are no-ops.
 */
import { useAnnotationStore } from "../useAnnotationStore";
import type { ToolHandler } from "../types";
import { createAnnotation } from "../types";

export const textTool: ToolHandler = {
  onMouseDown(pos) {
    const state = useAnnotationStore.getState();
    const annotation = createAnnotation(
      "text",
      { x: pos.x, y: pos.y, width: 200, height: 30 },
      state.currentColor,
      state.currentStrokeWidth,
      state.annotations.length + 1,
      {
        text: "",
        fontSize: state.currentFontSize,
        fontName: state.currentFontName,
      },
    );
    state.addAnnotation(annotation);
    state.selectAnnotation(annotation.id);
  },

  onMouseMove() {
    // No-op — text editing handled by Konva Text component.
  },

  onMouseUp() {
    // No-op.
  },

  cursor: "text",
};
