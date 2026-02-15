/**
 * ColorPicker — popover anchored to toolbar color button.
 * Preset swatches, hex input, opacity slider, recent colors.
 */
import React, { useCallback, useEffect, useRef, useState } from "react";
import { DSColorSwatch, DSTextField } from "@/components";
import styles from "./Annotation.module.css";

// 10 color presets matching the Swift app's COLOR_PRESETS
const COLOR_PRESETS = [
  "#FF3B30", // Red
  "#FF9500", // Orange
  "#FFCC00", // Yellow
  "#34C759", // Green
  "#00C7BE", // Teal
  "#007AFF", // Blue
  "#5856D6", // Indigo
  "#AF52DE", // Purple
  "#FF2D55", // Pink
  "#FFFFFF", // White
];

interface ColorPickerProps {
  anchor: DOMRect;
  currentColor: string;
  onSelect: (color: string) => void;
  onClose: () => void;
}

export const ColorPicker: React.FC<ColorPickerProps> = ({
  anchor,
  currentColor,
  onSelect,
  onClose,
}) => {
  const panelRef = useRef<HTMLDivElement>(null);
  const [hexInput, setHexInput] = useState(currentColor);
  const [opacity, setOpacity] = useState(100);
  const [recentColors, setRecentColors] = useState<string[]>(() => {
    try {
      const stored = localStorage.getItem("annotation-recent-colors");
      return stored ? JSON.parse(stored) : [];
    } catch {
      return [];
    }
  });

  // Sync hex input when external color changes
  useEffect(() => {
    setHexInput(currentColor);
  }, [currentColor]);

  const addToRecent = useCallback(
    (color: string) => {
      setRecentColors((prev) => {
        const next = [color, ...prev.filter((c) => c !== color)].slice(0, 5);
        try {
          localStorage.setItem("annotation-recent-colors", JSON.stringify(next));
        } catch {
          /* noop */
        }
        return next;
      });
    },
    []
  );

  const handlePresetClick = useCallback(
    (color: string) => {
      onSelect(color);
      addToRecent(color);
    },
    [onSelect, addToRecent]
  );

  const handleHexCommit = useCallback(() => {
    let hex = hexInput.trim();
    if (!hex.startsWith("#")) hex = `#${hex}`;
    // Validate hex
    if (/^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})$/.test(hex)) {
      onSelect(hex);
      addToRecent(hex);
    }
  }, [hexInput, onSelect, addToRecent]);

  const handleOpacityChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const val = Number(e.target.value);
      setOpacity(val);
      // Apply opacity to current color
      const alpha = Math.round((val / 100) * 255)
        .toString(16)
        .padStart(2, "0");
      const baseColor = currentColor.length === 9 ? currentColor.slice(0, 7) : currentColor;
      onSelect(val === 100 ? baseColor : `${baseColor}${alpha}`);
    },
    [currentColor, onSelect]
  );

  // Position popover to the right of the anchor
  const top = anchor.top;
  const left = anchor.right + 8;

  return (
    <>
      {/* Backdrop */}
      <div className={styles.colorPickerBackdrop} onClick={onClose} />

      {/* Popover */}
      <div
        ref={panelRef}
        className={styles.colorPicker}
        style={{ top, left, position: "fixed" }}
      >
        {/* Preset swatches */}
        <div className={styles.colorGrid}>
          {COLOR_PRESETS.map((color) => (
            <DSColorSwatch
              key={color}
              color={color}
              selected={currentColor === color}
              onClick={() => handlePresetClick(color)}
            />
          ))}
        </div>

        {/* Hex input + preview */}
        <div className={styles.colorHexRow}>
          <DSTextField
            value={hexInput}
            onChange={setHexInput}
            placeholder="#FF3B30"
            className={styles.colorHexInput}
          />
          <div
            className={styles.colorPreview}
            style={{ backgroundColor: currentColor }}
          />
        </div>

        {/* Commit hex on Enter */}
        <div style={{ display: "none" }}>
          <input
            onKeyDown={(e) => {
              if (e.key === "Enter") handleHexCommit();
            }}
          />
        </div>

        {/* Opacity slider */}
        <div className={styles.opacityRow}>
          <span className={styles.opacityRowLabel}>Opacity</span>
          <input
            type="range"
            min={0}
            max={100}
            step={1}
            value={opacity}
            onChange={handleOpacityChange}
            className={styles.opacityRowSlider}
          />
          <span className={styles.opacityValue}>{opacity}%</span>
        </div>

        {/* Recent colors */}
        {recentColors.length > 0 && (
          <div className={styles.recentColors}>
            <span className={styles.recentLabel}>Recent</span>
            {recentColors.map((color, i) => (
              <DSColorSwatch
                key={`${color}-${i}`}
                color={color}
                size="sm"
                selected={currentColor === color}
                onClick={() => handlePresetClick(color)}
              />
            ))}
          </div>
        )}
      </div>
    </>
  );
};
