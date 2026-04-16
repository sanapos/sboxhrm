import { Input } from "@/components/ui/input";
import { formatNumber, parseFormattedNumber } from "@/lib/utils";
import { InputHTMLAttributes, forwardRef } from "react";

interface MoneyInputProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange' | 'type'> {
  value: number | undefined;
  onChange: (value: number) => void;
}

export const MoneyInput = forwardRef<HTMLInputElement, MoneyInputProps>(
  ({ value, onChange, ...props }, ref) => {
    const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
      const numericValue = parseFormattedNumber(e.target.value);
      onChange(numericValue);
    };

    const displayValue = value !== undefined ? formatNumber(value) : '';

    return (
      <Input
        ref={ref}
        type="text"
        value={displayValue}
        onChange={handleChange}
        {...props}
      />
    );
  }
);

MoneyInput.displayName = "MoneyInput";
