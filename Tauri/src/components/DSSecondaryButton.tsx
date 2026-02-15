import React from "react";
import clsx from "clsx";
import styles from "./DSSecondaryButton.module.css";

interface DSSecondaryButtonProps {
  children: React.ReactNode;
  onClick?: () => void;
  disabled?: boolean;
  icon?: React.ReactNode;
  className?: string;
  danger?: boolean;
}

export const DSSecondaryButton = React.forwardRef<HTMLButtonElement, DSSecondaryButtonProps>(
  ({ children, onClick, disabled, icon, className, danger }, ref) => (
    <button
      ref={ref}
      type="button"
      className={clsx(styles.button, danger && styles.danger, disabled && styles.disabled, className)}
      onClick={onClick}
      disabled={disabled}
    >
      {icon && <span className={styles.icon}>{icon}</span>}
      {children}
    </button>
  )
);

DSSecondaryButton.displayName = "DSSecondaryButton";
