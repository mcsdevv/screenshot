import React from "react";
import clsx from "clsx";
import styles from "./DSIconButton.module.css";

interface DSIconButtonProps {
  icon: React.ReactNode;
  onClick?: () => void;
  selected?: boolean;
  disabled?: boolean;
  size?: "sm" | "md" | "lg";
  tooltip?: string;
  className?: string;
}

export const DSIconButton = React.forwardRef<HTMLButtonElement, DSIconButtonProps>(
  ({ icon, onClick, selected, disabled, size = "md", tooltip, className }, ref) => (
    <button
      ref={ref}
      type="button"
      className={clsx(styles.button, styles[size], selected && styles.selected, disabled && styles.disabled, className)}
      onClick={onClick}
      disabled={disabled}
      title={tooltip}
    >
      {icon}
    </button>
  )
);

DSIconButton.displayName = "DSIconButton";
