/**
 * Barrel export — maps each AnnotationTool to its ToolHandler.
 */
import type { AnnotationTool, ToolHandler } from "../types";
import { selectTool } from "./SelectTool";
import { cropTool } from "./CropTool";
import { rectTool } from "./RectTool";
import { circleTool } from "./CircleTool";
import { lineTool } from "./LineTool";
import { arrowTool } from "./ArrowTool";
import { textTool } from "./TextTool";
import { blurTool } from "./BlurTool";
import { pencilTool } from "./PencilTool";
import { highlighterTool } from "./HighlighterTool";
import { numberedStepTool } from "./NumberedStepTool";

export const toolHandlers: Record<AnnotationTool, ToolHandler> = {
  select: selectTool,
  crop: cropTool,
  rectangleOutline: rectTool,
  rectangleSolid: rectTool,
  circleOutline: circleTool,
  line: lineTool,
  arrow: arrowTool,
  text: textTool,
  blur: blurTool,
  pencil: pencilTool,
  highlighter: highlighterTool,
  numberedStep: numberedStepTool,
};
