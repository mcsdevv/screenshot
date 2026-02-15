/**
 * AnnotationCanvas — Konva.js canvas with 5 layers.
 *
 * Layers (bottom to top):
 *   1. Background image
 *   2. Annotations below selection
 *   3. Selection indicators (Transformer)
 *   4. Annotations above selection (none currently; reserved for future)
 *   5. Crop overlay
 */
import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Stage,
  Layer,
  Rect,
  Ellipse,
  Line,
  Arrow,
  Text,
  Transformer,
  Image as KonvaImage,
  Circle,
  Group,
} from "react-konva";
import Konva from "konva";
import { useAnnotationStore } from "./useAnnotationStore";
import type { Annotation, AnnotationTool, Point, Rect as RectType } from "./types";
import { createAnnotation, normalizeRect, constrainToAxis } from "./types";

interface AnnotationCanvasProps {
  image: HTMLImageElement;
  onMouseMove?: (x: number, y: number) => void;
}

export const AnnotationCanvas: React.FC<AnnotationCanvasProps> = ({
  image,
  onMouseMove,
}) => {
  const store = useAnnotationStore();
  const stageRef = useRef<Konva.Stage>(null);
  const transformerRef = useRef<Konva.Transformer>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const selectedShapeRef = useRef<Konva.Node | null>(null);

  // Drawing state (local, not in store — only committed on mouseUp)
  const [drawing, setDrawing] = useState(false);
  const [drawStart, setDrawStart] = useState<Point>({ x: 0, y: 0 });
  const [currentAnnotation, setCurrentAnnotation] = useState<Annotation | null>(null);
  const [stageSize, setStageSize] = useState({ width: 800, height: 600 });

  // Fit stage to container
  useEffect(() => {
    const fitStage = () => {
      if (!containerRef.current) return;
      setStageSize({
        width: containerRef.current.clientWidth,
        height: containerRef.current.clientHeight,
      });
    };
    fitStage();
    const ro = new ResizeObserver(fitStage);
    if (containerRef.current) ro.observe(containerRef.current);
    return () => ro.disconnect();
  }, []);

  // Attach transformer to selected annotation node
  useEffect(() => {
    const tr = transformerRef.current;
    if (!tr) return;

    if (!store.selectedAnnotationId || store.currentTool !== "select") {
      tr.nodes([]);
      tr.getLayer()?.batchDraw();
      return;
    }

    const stage = stageRef.current;
    if (!stage) return;

    const node = stage.findOne(`#${store.selectedAnnotationId}`);
    if (node) {
      tr.nodes([node]);
      selectedShapeRef.current = node;
    } else {
      tr.nodes([]);
      selectedShapeRef.current = null;
    }
    tr.getLayer()?.batchDraw();
  }, [store.selectedAnnotationId, store.currentTool, store.annotations]);

  // Image as Konva.Image
  const konvaImage = useMemo(() => {
    const img = new window.Image();
    img.src = image.src;
    return img;
  }, [image.src]);

  // Coordinate helpers
  const getPointerPos = useCallback((): Point => {
    const stage = stageRef.current;
    if (!stage) return { x: 0, y: 0 };
    const pos = stage.getPointerPosition();
    if (!pos) return { x: 0, y: 0 };
    const scale = store.zoom;
    const offset = store.offset;
    return {
      x: (pos.x - offset.x) / scale,
      y: (pos.y - offset.y) / scale,
    };
  }, [store.zoom, store.offset]);

  // Get cursor for current tool
  const getCursor = (): string => {
    switch (store.currentTool) {
      case "select":
        return "default";
      case "crop":
        return "crosshair";
      case "text":
        return "text";
      default:
        return "crosshair";
    }
  };

  // ---- Mouse handlers ----

  const handleMouseDown = useCallback(
    (e: Konva.KonvaEventObject<MouseEvent>) => {
      const pos = getPointerPos();
      const tool = store.currentTool;

      // Select tool: click on empty space deselects
      if (tool === "select") {
        if (e.target === e.target.getStage() || e.target.name() === "background") {
          store.selectAnnotation(null);
        }
        return;
      }

      // Text tool: single-click to place text
      if (tool === "text") {
        const annotation = createAnnotation(
          "text",
          { x: pos.x, y: pos.y, width: 200, height: 30 },
          store.currentColor,
          store.currentStrokeWidth,
          store.annotations.length,
          { text: "Text", fontSize: store.currentFontSize, fontName: store.currentFontName }
        );
        store.addAnnotation(annotation);
        store.setTool("select");
        return;
      }

      // Numbered step: single-click to place
      if (tool === "numberedStep") {
        const stepNum = store.stepCounter + 1;
        const annotation = createAnnotation(
          "numberedStep",
          { x: pos.x - 15, y: pos.y - 15, width: 30, height: 30 },
          store.currentColor,
          store.currentStrokeWidth,
          store.annotations.length,
          { stepNumber: stepNum }
        );
        store.addAnnotation(annotation);
        // Increment counter — store's addAnnotation doesn't do this automatically
        useAnnotationStore.setState({ stepCounter: stepNum });
        return;
      }

      // Drawing tools: start drag
      if (isDrawingTool(tool)) {
        setDrawing(true);
        setDrawStart(pos);

        const rect: RectType = { x: pos.x, y: pos.y, width: 0, height: 0 };
        const a = createAnnotation(
          tool as Exclude<AnnotationTool, "select" | "crop">,
          rect,
          store.currentColor,
          store.currentStrokeWidth,
          store.annotations.length,
          tool === "blur" ? { blurRadius: store.blurRadius } : undefined
        );

        // For pencil/highlighter, start the points array
        if (tool === "pencil" || tool === "highlighter") {
          a.points = [pos];
        }

        setCurrentAnnotation(a);
      }
    },
    [getPointerPos, store]
  );

  const handleMouseMove = useCallback(
    (e: Konva.KonvaEventObject<MouseEvent>) => {
      const pos = getPointerPos();
      onMouseMove?.(Math.round(pos.x), Math.round(pos.y));

      if (!drawing || !currentAnnotation) return;

      const shiftKey = e.evt.shiftKey;
      let endPos = pos;

      // Shift constraint for line/arrow
      if (
        shiftKey &&
        (currentAnnotation.type === "line" || currentAnnotation.type === "arrow")
      ) {
        endPos = constrainToAxis(drawStart, pos);
      }

      setCurrentAnnotation((prev) => {
        if (!prev) return null;
        const next = { ...prev };

        if (prev.type === "pencil" || prev.type === "highlighter") {
          next.points = [...prev.points, endPos];
        } else {
          next.rect = {
            x: drawStart.x,
            y: drawStart.y,
            width: endPos.x - drawStart.x,
            height: endPos.y - drawStart.y,
          };
        }
        return next;
      });
    },
    [drawing, currentAnnotation, drawStart, getPointerPos, onMouseMove]
  );

  const handleMouseUp = useCallback(() => {
    if (!drawing || !currentAnnotation) return;
    setDrawing(false);

    // Normalize rect (ensure positive width/height)
    const final = { ...currentAnnotation };
    if (final.type !== "pencil" && final.type !== "highlighter") {
      final.rect = normalizeRect(final.rect);
    }

    // Only add if has meaningful size (> 3px)
    const hasSize =
      final.type === "pencil" || final.type === "highlighter"
        ? final.points.length > 2
        : final.rect.width > 3 || final.rect.height > 3;

    if (hasSize) {
      store.addAnnotation(final);
    }

    setCurrentAnnotation(null);
  }, [drawing, currentAnnotation, store]);

  // Wheel to zoom
  const handleWheel = useCallback(
    (e: Konva.KonvaEventObject<WheelEvent>) => {
      e.evt.preventDefault();
      const stage = stageRef.current;
      if (!stage) return;

      const oldScale = store.zoom;
      const pointer = stage.getPointerPosition();
      if (!pointer) return;

      const scaleBy = 1.08;
      const direction = e.evt.deltaY > 0 ? -1 : 1;
      const newScale = direction > 0 ? oldScale * scaleBy : oldScale / scaleBy;
      const clampedScale = Math.max(0.25, Math.min(4, newScale));

      const mousePointTo = {
        x: (pointer.x - store.offset.x) / oldScale,
        y: (pointer.y - store.offset.y) / oldScale,
      };

      store.setZoom(clampedScale);
      store.setOffset({
        x: pointer.x - mousePointTo.x * clampedScale,
        y: pointer.y - mousePointTo.y * clampedScale,
      });
    },
    [store]
  );

  // Handle transform end (resize)
  const handleTransformEnd = useCallback(
    (annotation: Annotation, node: Konva.Node) => {
      const scaleX = node.scaleX();
      const scaleY = node.scaleY();
      node.scaleX(1);
      node.scaleY(1);

      const updated: Annotation = {
        ...annotation,
        rect: {
          x: node.x(),
          y: node.y(),
          width: Math.max(5, node.width() * scaleX),
          height: Math.max(5, node.height() * scaleY),
        },
      };
      store.updateAnnotation(updated);
    },
    [store]
  );

  // Handle drag end
  const handleDragEnd = useCallback(
    (annotation: Annotation, node: Konva.Node) => {
      const updated: Annotation = {
        ...annotation,
        rect: { ...annotation.rect, x: node.x(), y: node.y() },
      };
      store.updateAnnotation(updated);
    },
    [store]
  );

  // ---- Render individual annotation shapes ----

  const renderAnnotation = useCallback(
    (annotation: Annotation) => {
      const { id, type, rect, color, strokeWidth, isVisible } = annotation;
      if (!isVisible) return null;
      if (store.hiddenAnnotationIds.has(id)) return null;

      const common = {
        id,
        key: id,
        x: rect.x,
        y: rect.y,
        draggable: store.currentTool === "select",
        onClick: () => {
          store.selectAnnotation(id);
          store.setTool("select");
        },
        onDragEnd: (e: Konva.KonvaEventObject<DragEvent>) =>
          handleDragEnd(annotation, e.target),
        onTransformEnd: (e: Konva.KonvaEventObject<Event>) =>
          handleTransformEnd(annotation, e.target),
      };

      switch (type) {
        case "rectangleOutline":
          return (
            <Rect
              {...common}
              width={rect.width}
              height={rect.height}
              stroke={color}
              strokeWidth={strokeWidth}
              cornerRadius={2}
            />
          );

        case "rectangleSolid":
          return (
            <Rect
              {...common}
              width={rect.width}
              height={rect.height}
              fill={color}
              cornerRadius={2}
            />
          );

        case "circleOutline":
          return (
            <Ellipse
              {...common}
              x={rect.x + rect.width / 2}
              y={rect.y + rect.height / 2}
              radiusX={rect.width / 2}
              radiusY={rect.height / 2}
              stroke={color}
              strokeWidth={strokeWidth}
              draggable={store.currentTool === "select"}
              onClick={() => {
                store.selectAnnotation(id);
                store.setTool("select");
              }}
              onDragEnd={(e) => {
                const node = e.target;
                store.updateAnnotation({
                  ...annotation,
                  rect: {
                    ...rect,
                    x: node.x() - rect.width / 2,
                    y: node.y() - rect.height / 2,
                  },
                });
              }}
            />
          );

        case "line":
          return (
            <Line
              key={id}
              id={id}
              points={[rect.x, rect.y, rect.x + rect.width, rect.y + rect.height]}
              stroke={color}
              strokeWidth={strokeWidth}
              lineCap="round"
              draggable={store.currentTool === "select"}
              onClick={() => {
                store.selectAnnotation(id);
                store.setTool("select");
              }}
              onDragEnd={(e) => {
                const node = e.target;
                const dx = node.x();
                const dy = node.y();
                node.position({ x: 0, y: 0 });
                store.updateAnnotation({
                  ...annotation,
                  rect: {
                    x: rect.x + dx,
                    y: rect.y + dy,
                    width: rect.width,
                    height: rect.height,
                  },
                });
              }}
            />
          );

        case "arrow": {
          const arrowPoints = [
            rect.x,
            rect.y,
            rect.x + rect.width,
            rect.y + rect.height,
          ];
          return (
            <Arrow
              key={id}
              id={id}
              points={arrowPoints}
              stroke={color}
              fill={color}
              strokeWidth={strokeWidth}
              pointerLength={10 + strokeWidth}
              pointerWidth={10 + strokeWidth}
              lineCap="round"
              draggable={store.currentTool === "select"}
              onClick={() => {
                store.selectAnnotation(id);
                store.setTool("select");
              }}
              onDragEnd={(e) => {
                const node = e.target;
                const dx = node.x();
                const dy = node.y();
                node.position({ x: 0, y: 0 });
                store.updateAnnotation({
                  ...annotation,
                  rect: {
                    x: rect.x + dx,
                    y: rect.y + dy,
                    width: rect.width,
                    height: rect.height,
                  },
                });
              }}
            />
          );
        }

        case "text":
          return (
            <Text
              {...common}
              text={annotation.text ?? ""}
              fontSize={annotation.fontSize}
              fontFamily={annotation.fontName}
              fill={color}
              width={rect.width || undefined}
            />
          );

        case "blur":
          return (
            <Rect
              {...common}
              width={rect.width}
              height={rect.height}
              fill="rgba(0,0,0,0.25)"
              stroke="rgba(255,255,255,0.4)"
              strokeWidth={1}
              dash={[6, 4]}
            />
          );

        case "pencil":
          return (
            <Line
              key={id}
              id={id}
              points={annotation.points.flatMap((p) => [p.x, p.y])}
              stroke={color}
              strokeWidth={strokeWidth}
              lineCap="round"
              lineJoin="round"
              tension={0.5}
              draggable={store.currentTool === "select"}
              onClick={() => {
                store.selectAnnotation(id);
                store.setTool("select");
              }}
              onDragEnd={(e) => {
                const node = e.target;
                const dx = node.x();
                const dy = node.y();
                node.position({ x: 0, y: 0 });
                store.updateAnnotation({
                  ...annotation,
                  points: annotation.points.map((p) => ({
                    x: p.x + dx,
                    y: p.y + dy,
                  })),
                });
              }}
            />
          );

        case "highlighter":
          return (
            <Line
              key={id}
              id={id}
              points={annotation.points.flatMap((p) => [p.x, p.y])}
              stroke={color}
              strokeWidth={strokeWidth * 3}
              opacity={0.4}
              lineCap="round"
              lineJoin="round"
              tension={0.5}
              globalCompositeOperation="multiply"
              draggable={store.currentTool === "select"}
              onClick={() => {
                store.selectAnnotation(id);
                store.setTool("select");
              }}
              onDragEnd={(e) => {
                const node = e.target;
                const dx = node.x();
                const dy = node.y();
                node.position({ x: 0, y: 0 });
                store.updateAnnotation({
                  ...annotation,
                  points: annotation.points.map((p) => ({
                    x: p.x + dx,
                    y: p.y + dy,
                  })),
                });
              }}
            />
          );

        case "numberedStep": {
          const cx = rect.x + rect.width / 2;
          const cy = rect.y + rect.height / 2;
          const radius = 15;
          return (
            <Group
              key={id}
              id={id}
              x={cx}
              y={cy}
              draggable={store.currentTool === "select"}
              onClick={() => {
                store.selectAnnotation(id);
                store.setTool("select");
              }}
              onDragEnd={(e) => {
                const node = e.target;
                store.updateAnnotation({
                  ...annotation,
                  rect: {
                    x: node.x() - rect.width / 2,
                    y: node.y() - rect.height / 2,
                    width: rect.width,
                    height: rect.height,
                  },
                });
              }}
            >
              <Circle radius={radius} fill={color} />
              <Text
                text={String(annotation.stepNumber ?? "")}
                fontSize={16}
                fontStyle="bold"
                fill="#ffffff"
                align="center"
                verticalAlign="middle"
                width={radius * 2}
                height={radius * 2}
                offsetX={radius}
                offsetY={radius}
              />
            </Group>
          );
        }

        default:
          return null;
      }
    },
    [store, handleDragEnd, handleTransformEnd]
  );

  // Render the in-progress annotation during drawing
  const renderCurrentAnnotation = useCallback(() => {
    if (!currentAnnotation) return null;
    const { type, rect, color, strokeWidth, points } = currentAnnotation;

    switch (type) {
      case "rectangleOutline":
        return (
          <Rect
            x={rect.x}
            y={rect.y}
            width={rect.width}
            height={rect.height}
            stroke={color}
            strokeWidth={strokeWidth}
            cornerRadius={2}
            listening={false}
          />
        );
      case "rectangleSolid":
        return (
          <Rect
            x={rect.x}
            y={rect.y}
            width={rect.width}
            height={rect.height}
            fill={color}
            cornerRadius={2}
            listening={false}
          />
        );
      case "circleOutline":
        return (
          <Ellipse
            x={rect.x + rect.width / 2}
            y={rect.y + rect.height / 2}
            radiusX={Math.abs(rect.width / 2)}
            radiusY={Math.abs(rect.height / 2)}
            stroke={color}
            strokeWidth={strokeWidth}
            listening={false}
          />
        );
      case "line":
        return (
          <Line
            points={[rect.x, rect.y, rect.x + rect.width, rect.y + rect.height]}
            stroke={color}
            strokeWidth={strokeWidth}
            lineCap="round"
            listening={false}
          />
        );
      case "arrow":
        return (
          <Arrow
            points={[rect.x, rect.y, rect.x + rect.width, rect.y + rect.height]}
            stroke={color}
            fill={color}
            strokeWidth={strokeWidth}
            pointerLength={10 + strokeWidth}
            pointerWidth={10 + strokeWidth}
            lineCap="round"
            listening={false}
          />
        );
      case "blur":
        return (
          <Rect
            x={rect.x}
            y={rect.y}
            width={rect.width}
            height={rect.height}
            fill="rgba(0,0,0,0.25)"
            stroke="rgba(255,255,255,0.4)"
            strokeWidth={1}
            dash={[6, 4]}
            listening={false}
          />
        );
      case "pencil":
        return (
          <Line
            points={points.flatMap((p) => [p.x, p.y])}
            stroke={color}
            strokeWidth={strokeWidth}
            lineCap="round"
            lineJoin="round"
            tension={0.5}
            listening={false}
          />
        );
      case "highlighter":
        return (
          <Line
            points={points.flatMap((p) => [p.x, p.y])}
            stroke={color}
            strokeWidth={strokeWidth * 3}
            opacity={0.4}
            lineCap="round"
            lineJoin="round"
            tension={0.5}
            listening={false}
          />
        );
      default:
        return null;
    }
  }, [currentAnnotation]);

  // Crop overlay
  const renderCropOverlay = useCallback(() => {
    if (store.currentTool !== "crop" || !store.cropRect) return null;
    const cr = store.cropRect;
    const imgW = image.naturalWidth;
    const imgH = image.naturalHeight;

    return (
      <>
        {/* Darken area outside crop */}
        <Rect x={0} y={0} width={imgW} height={cr.y} fill="rgba(0,0,0,0.5)" listening={false} />
        <Rect x={0} y={cr.y} width={cr.x} height={cr.height} fill="rgba(0,0,0,0.5)" listening={false} />
        <Rect x={cr.x + cr.width} y={cr.y} width={imgW - cr.x - cr.width} height={cr.height} fill="rgba(0,0,0,0.5)" listening={false} />
        <Rect x={0} y={cr.y + cr.height} width={imgW} height={imgH - cr.y - cr.height} fill="rgba(0,0,0,0.5)" listening={false} />
        {/* Crop border */}
        <Rect
          x={cr.x}
          y={cr.y}
          width={cr.width}
          height={cr.height}
          stroke="rgba(255,255,255,0.8)"
          strokeWidth={1.5}
          dash={[8, 4]}
          listening={false}
        />
      </>
    );
  }, [store.currentTool, store.cropRect, image]);

  return (
    <div
      ref={containerRef}
      style={{ width: "100%", height: "100%", cursor: getCursor() }}
    >
      <Stage
        ref={stageRef}
        width={stageSize.width}
        height={stageSize.height}
        scaleX={store.zoom}
        scaleY={store.zoom}
        x={store.offset.x}
        y={store.offset.y}
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onWheel={handleWheel}
      >
        {/* Layer 1: Background image */}
        <Layer>
          <KonvaImage
            image={konvaImage}
            name="background"
            width={image.naturalWidth}
            height={image.naturalHeight}
            listening={true}
          />
        </Layer>

        {/* Layer 2: Committed annotations */}
        <Layer>
          {store.annotations.map((a) => renderAnnotation(a))}
        </Layer>

        {/* Layer 3: Selection transformer */}
        <Layer>
          <Transformer
            ref={transformerRef}
            rotateEnabled={false}
            borderStroke="var(--ds-accent, #00d4ff)"
            borderStrokeWidth={1.5}
            anchorFill="#ffffff"
            anchorStroke="#00d4ff"
            anchorSize={8}
            anchorCornerRadius={2}
            keepRatio={false}
            enabledAnchors={[
              "top-left",
              "top-right",
              "bottom-left",
              "bottom-right",
              "top-center",
              "bottom-center",
              "middle-left",
              "middle-right",
            ]}
          />
        </Layer>

        {/* Layer 4: Current drawing preview */}
        <Layer listening={false}>
          {renderCurrentAnnotation()}
        </Layer>

        {/* Layer 5: Crop overlay */}
        <Layer listening={false}>
          {renderCropOverlay()}
        </Layer>
      </Stage>
    </div>
  );
};

// ---- Helpers ----

function isDrawingTool(tool: AnnotationTool): boolean {
  return [
    "rectangleOutline",
    "rectangleSolid",
    "circleOutline",
    "line",
    "arrow",
    "blur",
    "pencil",
    "highlighter",
  ].includes(tool);
}
