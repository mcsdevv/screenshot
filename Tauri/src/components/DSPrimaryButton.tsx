import React from "react";
import clsx from "clsx";
import styles from "./DSPrimaryButton.module.css";

interface DSPrimaryButtonProps {
  children: React.ReactNode;
  onClick?: () => void;
  disabled?: boolean;
  icon?: React.ReactNode;
  size?: "sm" | "md" | "lg";
  className?: string;
  type?: "button" | "submit";
}

export const DSPrimaryButton = React.forwardRef<HTMLButtonElement, DSPrimaryButtonProps>(
  ({ children, onClick, disabled, icon, size = "md", className, type = "button" }, ref) => (
    <button
      ref={ref}
      type={type}
      className={clsx(styles.button, styles[size], disabled && styles.disabled, className)}
      onClick={onClick}
      disabled={disabled}
    >
      {icon && <span className={styles.icon}>{icon}</span>}
      {children}
    </button>
  )
);

DSPrimaryButton.displayName = "DSPrimaryButton";
