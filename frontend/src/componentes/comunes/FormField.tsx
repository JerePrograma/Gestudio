import type { InputHTMLAttributes } from "react";

interface FormFieldProps extends InputHTMLAttributes<HTMLInputElement> {
  label: string;
  error?: string;
}

const FormField = ({ id, label, error, className = "", ...props }: FormFieldProps) => {
  const errorId = error && id ? `${id}-error` : undefined;

  return (
    <div className="auth-label">
      <label htmlFor={id}>{label}</label>
      <input
        {...props}
        id={id}
        className={`form-input ${className}`}
        aria-invalid={Boolean(error)}
        aria-describedby={errorId}
      />
      {error && <span id={errorId} className="auth-error">{error}</span>}
    </div>
  );
};

export default FormField;
