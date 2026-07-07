import type { ReactNode } from "react";

interface FilterBarProps {
  children: ReactNode;
  label?: string;
}

const FilterBar = ({ children, label = "Filtros" }: FilterBarProps) => (
  <section className="filter-bar" aria-label={label}>
    {children}
  </section>
);

export default FilterBar;
