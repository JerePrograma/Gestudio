import { Search } from "lucide-react";
import type { InputHTMLAttributes } from "react";

interface SearchInputProps extends Omit<InputHTMLAttributes<HTMLInputElement>, "type"> {
  label?: string;
}

const SearchInput = ({ label = "Buscar", id = "search", ...props }: SearchInputProps) => (
  <label className="field-group search-input" htmlFor={id}>
    <span className="sr-only">{label}</span>
    <Search aria-hidden="true" />
    <input {...props} id={id} type="search" className="form-input" />
  </label>
);

export default SearchInput;
