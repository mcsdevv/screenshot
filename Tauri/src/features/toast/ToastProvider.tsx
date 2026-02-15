import React, { createContext, useCallback, useContext, useState } from "react";
import { ToastView } from "./ToastView";
import styles from "./Toast.module.css";

interface Toast {
  id: string;
  icon: string;
  message: string;
  color: string;
}

interface ToastContextValue {
  showToast: (icon: string, message: string, color?: string) => void;
}

const ToastContext = createContext<ToastContextValue>({ showToast: () => {} });

export const useToast = () => useContext(ToastContext);

export const ToastProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const showToast = useCallback((icon: string, message: string, color = "var(--ds-accent)") => {
    const id = crypto.randomUUID();
    setToasts((prev) => {
      const next = [...prev, { id, icon, message, color }];
      return next.slice(-3); // max 3
    });

    setTimeout(() => {
      setToasts((prev) => prev.filter((t) => t.id !== id));
    }, 1800);
  }, []);

  return (
    <ToastContext.Provider value={{ showToast }}>
      {children}
      <div className={styles.container}>
        {toasts.map((t) => (
          <ToastView key={t.id} icon={t.icon} message={t.message} color={t.color} />
        ))}
      </div>
    </ToastContext.Provider>
  );
};
