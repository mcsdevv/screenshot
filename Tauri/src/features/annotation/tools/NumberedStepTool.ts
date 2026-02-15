/**
 * Numbered step tool — single-click placement of numbered circles.
 * Step number auto-increments from the store's stepCounter.
 */
import { useAnnotationStore } from "../useAnnotationStore";
import type { ToolHandler } from "../types";
import { createAnnotation } from "../types";

/** Diameter of the numbered step circle (image-space pixels). */
const STEP_SIZE = 30;

export const numberedStepTool: ToolHandler = {
  onMouseDown(pos) {
    const state = useAnnotationStore.getState();
    const stepNumber = state.stepCounter + 1;
    const annotation = createAnnotation(
      "numberedStep",
      { x: pos.x - STEP_SIZE / 2, y: pos.y - STEP_SIZE / 2, width: STEP_SIZE, height: STEP_SIZE },
      state.currentColor,
      state.currentStrokeWidth,
      state.annotations.length + 1,
      { stepNumber },
    );
    state.addAnnotation(annotation);
    // Advance step counter in store (Zustand direct set via internal method)
    useAnnotationStore.setState({ stepCounter: stepNumber });
  },

  onMouseMove() {
    // No-op — single-click placement.
  },

  onMouseUp() {
    // No-op.
  },

  cursor: "crosshair",
};
