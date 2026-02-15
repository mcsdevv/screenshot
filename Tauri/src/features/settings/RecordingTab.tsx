import React from "react";
import clsx from "clsx";
import { DSChip, DSDivider } from "@/components";
import { useSettingsStore } from "@/stores/settingsStore";
import styles from "./Settings.module.css";

const QUALITY_OPTIONS = [
  { value: "low" as const, label: "Low (720p)" },
  { value: "medium" as const, label: "Medium (1080p)" },
  { value: "high" as const, label: "High (Native)" },
];

const FPS_OPTIONS = [
  { value: 30 as const, label: "30 FPS" },
  { value: 60 as const, label: "60 FPS" },
];

export const RecordingTab: React.FC = () => {
  const {
    recordingQuality,
    recordingFPS,
    recordShowCursor,
    recordMicrophone,
    recordSystemAudio,
    showMouseClicks,
    setSetting,
  } = useSettingsStore();

  return (
    <>
      <section className={styles.section}>
        <h3 className={styles.sectionTitle}>Video</h3>

        <div className={styles.row}>
          <span className={styles.label}>Quality</span>
          <div className={styles.chipGroup}>
            {QUALITY_OPTIONS.map((opt) => (
              <DSChip
                key={opt.value}
                label={opt.label}
                selected={recordingQuality === opt.value}
                onClick={() => setSetting("recordingQuality", opt.value)}
              />
            ))}
          </div>
        </div>

        <div className={styles.row}>
          <span className={styles.label}>Frame rate</span>
          <div className={styles.chipGroup}>
            {FPS_OPTIONS.map((opt) => (
              <DSChip
                key={opt.value}
                label={opt.label}
                selected={recordingFPS === opt.value}
                onClick={() => setSetting("recordingFPS", opt.value)}
              />
            ))}
          </div>
        </div>

        <div className={styles.row}>
          <span className={styles.label}>Show cursor</span>
          <button
            className={clsx(styles.toggle, recordShowCursor && styles.toggleOn)}
            onClick={() => setSetting("recordShowCursor", !recordShowCursor)}
          />
        </div>
      </section>

      <DSDivider />

      <section className={styles.section} style={{ marginTop: "var(--ds-spacing-xl)" }}>
        <h3 className={styles.sectionTitle}>Audio</h3>

        <div className={styles.row}>
          <span className={styles.label}>Record microphone</span>
          <button
            className={clsx(styles.toggle, recordMicrophone && styles.toggleOn)}
            onClick={() => setSetting("recordMicrophone", !recordMicrophone)}
          />
        </div>

        <div className={styles.row}>
          <span className={styles.label}>Record system audio</span>
          <button
            className={clsx(styles.toggle, recordSystemAudio && styles.toggleOn)}
            onClick={() => setSetting("recordSystemAudio", !recordSystemAudio)}
          />
        </div>
      </section>

      <DSDivider />

      <section className={styles.section} style={{ marginTop: "var(--ds-spacing-xl)" }}>
        <h3 className={styles.sectionTitle}>Visual Feedback</h3>

        <div className={styles.row}>
          <span className={styles.label}>Highlight mouse clicks</span>
          <button
            className={clsx(styles.toggle, showMouseClicks && styles.toggleOn)}
            onClick={() => setSetting("showMouseClicks", !showMouseClicks)}
          />
        </div>

        <div className={styles.row}>
          <span className={styles.label}>Keystroke overlay</span>
          <span className={styles.description} style={{ marginTop: 0 }}>Unavailable</span>
        </div>
      </section>
    </>
  );
};
