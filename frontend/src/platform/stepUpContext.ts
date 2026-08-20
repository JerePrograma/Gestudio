import { createContext, useContext } from "react";
import type { StepUpDescriptor, StepUpHeaders } from "./platformTypes";

export interface StepUpContextValue {
  executeWithStepUp: <T>(
    descriptor: StepUpDescriptor,
    operation: (headers: StepUpHeaders) => Promise<T>,
  ) => Promise<T>;
}

export const StepUpContext = createContext<StepUpContextValue | null>(null);

export const useStepUp = (): StepUpContextValue => {
  const value = useContext(StepUpContext);
  if (!value) throw new Error("useStepUp debe usarse dentro de StepUpProvider");
  return value;
};
