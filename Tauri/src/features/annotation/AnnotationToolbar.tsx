/**
 * AnnotationToolbar — left sidebar with tool buttons, color, stroke, and options.
 */
import React, { useState } from "react";
import clsx from "clsx";
import { useAnnotationStore } from "./useAnnotationStore";
import type { AnnotationTool } from "./types";
import { ColorPicker } from "./ColorPicker";
import styles from "./Annotation.module.css";

// Tool definitions grouped logically
interface ToolDef {
  tool: AnnotationTool;
  icon: React.ReactNode;
  tooltip: string;
}

const POINTER_TOOLS: ToolDef[] = [
  { tool: "select", icon: <CursorIcon />, tooltip: "Select (V)" },
  { tool: "crop", icon: <CropIcon />, tooltip: "Crop (C)" },
];

const SHAPE_TOOLS: ToolDef[] = [
  { tool: "rectangleOutline", icon: <RectIcon />, tooltip: "Rectangle (R)" },
  { tool: "circleOutline", icon: <CircleIcon />, tooltip: "Circle (O)" },
  { tool: "line", icon: <LineIcon />, tooltip: "Line (L)" },
  { tool: "arrow", icon: <ArrowIcon />, tooltip: "Arrow (A)" },
];

const CONTENT_TOOLS: ToolDef[] = [
  { tool: "text", icon: <TextIcon />, tooltip: "Text (T)" },
  { tool: "numberedStep", icon: <StepIcon />, tooltip: "Numbered Step (#)" },
];

const FREEFORM_TOOLS: ToolDef[] = [
  { tool: "pencil", icon: <PencilIcon />, tooltip: "Pencil (P)" },
  { tool: "highlighter", icon: <HighlighterIcon />, tooltip: "Highlighter (H)" },
];

const EFFECT_TOOLS: ToolDef[] = [
  { tool: "blur", icon: <BlurIcon />, tooltip: "Blur (B)" },
];

// Stroke presets
const STROKE_PRESETS = [
  { label: "Thin", width: 1.5, height: 1 },
  { label: "Medium", width: 3, height: 2 },
  { label: "Thick", width: 6, height: 4 },
];

export const AnnotationToolbar: React.FC = () => {
  const store = useAnnotationStore();
  const [showColorPicker, setShowColorPicker] = useState(false);
  const [colorPickerAnchor, setColorPickerAnchor] = useState<DOMRect | null>(null);

  const handleToolClick = (tool: AnnotationTool) => {
    store.setTool(tool);
  };

  const handleColorTriggerClick = (e: React.MouseEvent<HTMLButtonElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    setColorPickerAnchor(rect);
    setShowColorPicker((prev) => !prev);
  };

  const handleColorSelect = (color: string) => {
    store.setColor(color);
    // Also update selected annotation's color
    if (store.selectedAnnotationId) {
      const ann = store.annotations.find((a) => a.id === store.selectedAnnotationId);
      if (ann) {
        store.updateAnnotation({ ...ann, color });
      }
    }
  };

  const renderToolButton = (def: ToolDef) => {
    const isActive = store.currentTool === def.tool;
    return (
      <button
        key={def.tool}
        className={isActive ? styles.toolButtonActive : styles.toolButton}
        onClick={() => handleToolClick(def.tool)}
        title={def.tooltip}
      >
        {def.icon}
      </button>
    );
  };

  const renderToolGroup = (tools: ToolDef[]) => (
    <div className={styles.toolGroup}>
      {tools.map(renderToolButton)}
    </div>
  );

  const isTextActive =
    store.currentTool === "text" ||
    store.annotations.find((a) => a.id === store.selectedAnnotationId)?.type === "text";

  return (
    <div className={styles.toolbar}>
      {/* Pointer tools */}
      {renderToolGroup(POINTER_TOOLS)}
      <div className={styles.toolDivider} />

      {/* Shape tools */}
      {renderToolGroup(SHAPE_TOOLS)}
      <div className={styles.toolDivider} />

      {/* Content tools */}
      {renderToolGroup(CONTENT_TOOLS)}
      <div className={styles.toolDivider} />

      {/* Freeform tools */}
      {renderToolGroup(FREEFORM_TOOLS)}
      <div className={styles.toolDivider} />

      {/* Effect tools */}
      {renderToolGroup(EFFECT_TOOLS)}
      <div className={styles.toolDivider} />

      {/* ---- Properties ---- */}
      <div className={styles.toolProperties}>
        {/* Color trigger */}
        <span className={styles.propertyLabel}>Color</span>
        <button
          className={styles.colorTrigger}
          style={{ backgroundColor: store.currentColor }}
          onClick={handleColorTriggerClick}
          title="Color"
        />

        {/* Stroke width */}
        <span className={styles.propertyLabel}>Stroke</span>
        <div className={styles.strokeGroup}>
          {STROKE_PRESETS.map((preset) => (
            <button
              key={preset.label}
              className={
                store.currentStrokeWidth === preset.width
                  ? styles.strokeButtonActive
                  : styles.strokeButton
              }
              onClick={() => store.setStrokeWidth(preset.width)}
              title={preset.label}
            >
              <div
                className={styles.strokeLine}
                style={{ width: 16, height: preset.height }}
              />
            </button>
          ))}
        </div>

        {/* Font size (when text tool active) */}
        {isTextActive && (
          <>
            <span className={styles.propertyLabel}>Size</span>
            <select
              value={store.currentFontSize}
              onChange={(e) => store.setFontSize(Number(e.target.value))}
              style={{
                width: 40,
                background: "var(--ds-background-secondary)",
                border: "1px solid var(--ds-border)",
                borderRadius: "var(--ds-radius-xs)",
                color: "var(--ds-text-primary)",
                font: "var(--ds-font-mono)",
                padding: "2px",
                cursor: "pointer",
                textAlign: "center",
              }}
            >
              {[12, 14, 16, 18, 24, 32, 48, 64].map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
          </>
        )}

        {/* Opacity (for blur) */}
        {store.currentTool === "blur" && (
          <>
            <span className={styles.propertyLabel}>Radius</span>
            <div className={styles.opacitySlider}>
              <input
                type="range"
                min={5}
                max={30}
                step={1}
                value={store.blurRadius}
                onChange={(e) => store.setBlurRadius(Number(e.target.value))}
              />
            </div>
          </>
        )}
      </div>

      {/* Color picker popover */}
      {showColorPicker && colorPickerAnchor && (
        <ColorPicker
          anchor={colorPickerAnchor}
          currentColor={store.currentColor}
          onSelect={handleColorSelect}
          onClose={() => setShowColorPicker(false)}
        />
      )}
    </div>
  );
};

/* ---- Tool SVG Icons (16x16) ---- */

function CursorIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <path d="M3 2l2 12 2.5-4.5L12 7 3 2Z" stroke="currentColor" strokeWidth="1.3" strokeLinejoin="round" />
    </svg>
  );
}

function CropIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <path d="M5 1v10h10M1 5h10v10" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
    </svg>
  );
}

function RectIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <rect x="2.5" y="3.5" width="11" height="9" rx="1" stroke="currentColor" strokeWidth="1.3" />
    </svg>
  );
}

function CircleIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <ellipse cx="8" cy="8" rx="5.5" ry="5.5" stroke="currentColor" strokeWidth="1.3" />
    </svg>
  );
}

function LineIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <line x1="3" y1="13" x2="13" y2="3" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
    </svg>
  );
}

function ArrowIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <path d="M3 13L13 3M13 3H7M13 3v6" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function TextIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <path d="M3 4h10M8 4v9M5 13h6" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
    </svg>
  );
}

function StepIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <circle cx="8" cy="8" r="5.5" stroke="currentColor" strokeWidth="1.3" />
      <text x="8" y="11.5" textAnchor="middle" fill="currentColor" fontSize="9" fontWeight="bold">1</text>
    </svg>
  );
}

function PencilIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <path d="M11.5 2.5l2 2-8 8-3 1 1-3 8-8Z" stroke="currentColor" strokeWidth="1.3" strokeLinejoin="round" />
    </svg>
  );
}

function HighlighterIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <path d="M3 10l6-6 3 3-6 6H3v-3Z" stroke="currentColor" strokeWidth="1.3" strokeLinejoin="round" />
      <path d="M9 4l3-2 2 2-2 3" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
    </svg>
  );
}

function BlurIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <circle cx="5" cy="5" r="1.5" fill="currentColor" opacity="0.3" />
      <circle cx="11" cy="5" r="1.5" fill="currentColor" opacity="0.5" />
      <circle cx="8" cy="8" r="2" fill="currentColor" opacity="0.7" />
      <circle cx="5" cy="11" r="1.5" fill="currentColor" opacity="0.5" />
      <circle cx="11" cy="11" r="1.5" fill="currentColor" opacity="0.3" />
    </svg>
  );
}
