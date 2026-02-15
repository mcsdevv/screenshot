import React from "react";
import clsx from "clsx";
import styles from "./DSColorSwatch.module.css";

interface DSColorSwatchProps {
  color: string;
  selected?: boolean;
  onClick?: () => void;
  size?: "sm" | "md" | "lg";
}

export const DSColorSwatch: React.FC<DSColorSwatchProps> = ({
  color,
  selected,
  onClick,
  size = "md",
}) => (
  <button
    type="button"
    className={clsx(styles.swatch, styles[size], selected && styles.selected)}
    onClick={onClick}
    style={{ "--swatch-color": color } as React.CSSProperties}
  >
    <div className={styles.inner} />
  </button>
);
