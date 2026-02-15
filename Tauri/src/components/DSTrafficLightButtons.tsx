import React, { useState } from "react";
import styles from "./DSTrafficLightButtons.module.css";

interface DSTrafficLightButtonsProps {
  onClose?: () => void;
  onMinimize?: () => void;
  onZoom?: () => void;
}

export const DSTrafficLightButtons: React.FC<DSTrafficLightButtonsProps> = ({
  onClose,
  onMinimize,
  onZoom,
}) => {
  const [hovered, setHovered] = useState(false);

  return (
    <div
      className={styles.row}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      <button className={styles.close} onClick={onClose} title="Close">
        {hovered && <span className={styles.icon}>×</span>}
      </button>
      <button className={styles.minimize} onClick={onMinimize} title="Minimize">
        {hovered && <span className={styles.icon}>−</span>}
      </button>
      <button className={styles.zoom} onClick={onZoom} title="Zoom">
        {hovered && <span className={styles.icon}>+</span>}
      </button>
    </div>
  );
};
