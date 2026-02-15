import React from "react";
import clsx from "clsx";
import styles from "./DSChip.module.css";

interface DSChipProps {
  label: string;
  selected?: boolean;
  onClick?: () => void;
  color?: string;
}

export const DSChip: React.FC<DSChipProps> = ({ label, selected, onClick, color }) => (
  <button
    type="button"
    className={clsx(styles.chip, selected && styles.selected)}
    onClick={onClick}
    style={color ? { "--chip-color": color } as React.CSSProperties : undefined}
  >
    {label}
  </button>
);
