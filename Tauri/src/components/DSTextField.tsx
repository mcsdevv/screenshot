import React from "react";
import clsx from "clsx";
import styles from "./DSTextField.module.css";

interface DSTextFieldProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  label?: string;
  type?: "text" | "password" | "number" | "search";
  icon?: React.ReactNode;
  className?: string;
  disabled?: boolean;
}

export const DSTextField = React.forwardRef<HTMLInputElement, DSTextFieldProps>(
  ({ value, onChange, placeholder, label, type = "text", icon, className, disabled }, ref) => (
    <div className={clsx(styles.wrapper, className)}>
      {label && <label className={styles.label}>{label}</label>}
      <div className={clsx(styles.inputWrapper, disabled && styles.disabled)}>
        {icon && <span className={styles.icon}>{icon}</span>}
        <input
          ref={ref}
          type={type}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={placeholder}
          className={styles.input}
          disabled={disabled}
        />
      </div>
    </div>
  )
);

DSTextField.displayName = "DSTextField";
