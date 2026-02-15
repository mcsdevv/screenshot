import React from "react";
import clsx from "clsx";
import { DSChip, DSDivider } from "@/components";
import { useSettingsStore } from "@/stores/settingsStore";
import styles from "./Settings.module.css";

const IMAGE_FORMATS = [
  { value: "png" as const, label: "PNG" },
  { value: "jpeg" as const, label: "JPEG" },
  { value: "tiff" as const, label: "TIFF" },
];

export const CaptureTab: React.FC = () => {
  const { showCursor, captureFormat, jpegQuality, setSetting } = useSettingsStore();

  return (
    <>
      <section className={styles.section}>
        <h3 className={styles.sectionTitle}>Capture Options</h3>
        <div className={styles.row}>
          <span className={styles.label}>Include cursor in screenshots</span>
          <button
            className={clsx(styles.toggle, showCursor && styles.toggleOn)}
            onClick={() => setSetting("showCursor", !showCursor)}
          />
        </div>
      </section>

      <DSDivider />

      <section className={styles.section} style={{ marginTop: "var(--ds-spacing-xl)" }}>
        <h3 className={styles.sectionTitle}>Image Format</h3>
        <div className={styles.row}>
          <span className={styles.label}>Default format</span>
          <div className={styles.chipGroup}>
            {IMAGE_FORMATS.map((fmt) => (
              <DSChip
                key={fmt.value}
                label={fmt.label}
                selected={captureFormat === fmt.value}
                onClick={() => setSetting("captureFormat", fmt.value)}
              />
            ))}
          </div>
        </div>

        {captureFormat === "jpeg" && (
          <div className={styles.row}>
            <span className={styles.label}>JPEG quality</span>
            <div className={styles.sliderRow}>
              <input
                type="range"
                className={styles.slider}
                min={10}
                max={100}
                step={10}
                value={Math.round(jpegQuality * 100)}
                onChange={(e) => setSetting("jpegQuality", Number(e.target.value) / 100)}
              />
              <span className={styles.sliderValue}>{Math.round(jpegQuality * 100)}%</span>
            </div>
          </div>
        )}
      </section>
    </>
  );
};
