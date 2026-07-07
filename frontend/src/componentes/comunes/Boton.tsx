import React from "react";
import clsx from "clsx";

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  secondary?: boolean;
  children: React.ReactNode;
}

const Boton = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ secondary, children, className, ...props }, ref) => {
    const hasExplicitVariant = /\bpage-button(?:-secondary|-danger|-ghost)?\b/.test(className ?? "");
    const variantClass = hasExplicitVariant
      ? ""
      : secondary
        ? "page-button-secondary"
        : "page-button";

    return (
      <button
        ref={ref}
        className={clsx(
          "button-base",
          variantClass,
          className
        )}
        {...props}
      >
        {children}
      </button>
    );
  }
);

Boton.displayName = "Boton";

export default React.memo(Boton);
