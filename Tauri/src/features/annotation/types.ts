/**
 * Annotation types — mirroring ScreenCapture/Models/AnnotationTypes.swift
 */

export type AnnotationType =
  | "rectangleOutline"
  | "rectangleSolid"
  | "circleOutline"
  | "line"
  | "arrow"
  | "text"
  | "blur"
  | "pencil"
  | "highlighter"
  | "numberedStep";

export type AnnotationTool = "select" | "crop" | AnnotationType;

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface Point {
  x: number;
  y: number;
}

export interface Size {
  width: number;
  height: number;
}

export interface Annotation {
  readonly id: string;
  type: AnnotationType;
  rect: Rect;
  color: string;
  strokeWidth: number;
  text?: string;
  fontSize: number;
  fontName: string;
  points: Point[];
  stepNumber?: number;
  blurRadius: number;
  creationOrder: number;
  isNumberLocked: boolean;
  name?: string;
  isVisible: boolean;
}

export interface AnnotationDocument {
  version: number;
  annotations: Annotation[];
  imageHash: string;
}

export type HandlePosition =
  | "topLeft"
  | "topRight"
  | "bottomLeft"
  | "bottomRight"
  | "top"
  | "bottom"
  | "left"
  | "right";

export interface ToolHandler {
  onMouseDown: (pos: Point, shiftKey: boolean) => void;
  onMouseMove: (pos: Point, shiftKey: boolean) => void;
  onMouseUp: (pos: Point) => void;
  cursor: string;
}

export function createAnnotation(
  type: AnnotationType,
  rect: Rect,
  color: string,
  strokeWidth: number,
  creationOrder: number,
  extra?: Partial<Annotation>
): Annotation {
  return {
    id: crypto.randomUUID(),
    type,
    rect,
    color,
    strokeWidth,
    fontSize: 16,
    fontName: "system-ui",
    points: [],
    blurRadius: 10,
    creationOrder,
    isNumberLocked: false,
    isVisible: true,
    ...extra,
  };
}

export function normalizeRect(rect: Rect): Rect {
  return {
    x: rect.width < 0 ? rect.x + rect.width : rect.x,
    y: rect.height < 0 ? rect.y + rect.height : rect.y,
    width: Math.abs(rect.width),
    height: Math.abs(rect.height),
  };
}

export function constrainToAxis(start: Point, end: Point): Point {
  const dx = Math.abs(end.x - start.x);
  const dy = Math.abs(end.y - start.y);
  return dx >= dy ? { x: end.x, y: start.y } : { x: start.x, y: end.y };
}
