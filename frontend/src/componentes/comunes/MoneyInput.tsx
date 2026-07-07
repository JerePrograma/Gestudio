import type { FocusEvent } from "react";
import { normalizeMoneyInput } from "../../utils/money";
import FormField from "./FormField";

interface MoneyInputProps {
  id: string;
  label: string;
  value: string;
  onChange: (value: string) => void;
  error?: string;
  required?: boolean;
  disabled?: boolean;
}

const MoneyInput = ({ id, label, value, onChange, ...props }: MoneyInputProps) => {
  const normalize = (event: FocusEvent<HTMLInputElement>) => {
    const normalized = normalizeMoneyInput(event.target.value);
    if (normalized !== null) onChange(normalized);
  };

  return (
    <FormField
      {...props}
      id={id}
      label={label}
      type="text"
      inputMode="decimal"
      autoComplete="off"
      value={value}
      onChange={(event) => onChange(event.target.value)}
      onBlur={normalize}
    />
  );
};

export default MoneyInput;
