import axios from "axios";
import * as Dialog from "@radix-ui/react-dialog";
import { ShieldCheck, X } from "lucide-react";
import {
  useCallback,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { getApiErrorMessage } from "../api/apiError";
import Boton from "../componentes/comunes/Boton";
import { platformApi } from "./platformApi";
import type {
  StepUpChallenge,
  StepUpDescriptor,
  StepUpHeaders,
} from "./platformTypes";
import { StepUpContext } from "./stepUpContext";

interface PendingOperation {
  descriptor: StepUpDescriptor;
  challenge: StepUpChallenge;
  retry: (headers: StepUpHeaders) => Promise<void>;
  reject: (reason: unknown) => void;
}

const isStepUpRequired = (error: unknown): boolean =>
  axios.isAxiosError(error) && error.response?.status === 428;

export const StepUpProvider = ({ children }: { children: ReactNode }) => {
  const [pending, setPending] = useState<PendingOperation | null>(null);
  const [code, setCode] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const codeRef = useRef<HTMLInputElement>(null);

  const executeWithStepUp = useCallback(
    async <T,>(descriptor: StepUpDescriptor,
      operation: (headers: StepUpHeaders) => Promise<T>): Promise<T> => {
      if (pending) throw new Error("Ya hay una verificación reforzada en curso");
      const headers: StepUpHeaders = { "Idempotency-Key": descriptor.idempotencyKey };

      try {
        return await operation(headers);
      } catch (operationError) {
        if (!isStepUpRequired(operationError)) throw operationError;
        const challenge = await platformApi.createStepUpChallenge(descriptor);
        return await new Promise<T>((resolve, reject) => {
          setCode("");
          setError("");
          setPending({
            descriptor,
            challenge,
            retry: async (retryHeaders) => resolve(await operation(retryHeaders)),
            reject,
          });
        });
      }
    },
    [pending],
  );

  const close = () => {
    if (busy || !pending) return;
    pending.reject(new Error("Verificación reforzada cancelada"));
    setPending(null);
    setCode("");
    setError("");
  };

  const verify = async () => {
    if (!pending || !/^\d{6}$/.test(code)) {
      setError("Ingresá el código TOTP de 6 dígitos.");
      codeRef.current?.focus();
      return;
    }

    setBusy(true);
    setError("");
    try {
      const proof = await platformApi.verifyStepUpChallenge(pending.challenge.challengeId, code);
      await pending.retry({
        "Idempotency-Key": pending.descriptor.idempotencyKey,
        "X-Step-Up-Token": proof.stepUpToken,
      });
      setPending(null);
      setCode("");
    } catch (verificationError) {
      const message = getApiErrorMessage(
        verificationError,
        "No se pudo verificar el código o completar la operación.",
      );
      setError(message);
      codeRef.current?.focus();
      if (axios.isAxiosError(verificationError) && [403, 409].includes(verificationError.response?.status ?? 0)) {
        setCode("");
      }
    } finally {
      setBusy(false);
    }
  };

  return (
    <StepUpContext.Provider value={{ executeWithStepUp }}>
      {children}
      <Dialog.Root open={pending !== null} onOpenChange={(open) => !open && close()}>
        <Dialog.Portal>
          <Dialog.Overlay className="fixed inset-0 z-[60] bg-foreground/50 backdrop-blur-sm" />
          <Dialog.Content className="fixed left-1/2 top-1/2 z-[60] w-[min(28rem,calc(100vw-2rem))] -translate-x-1/2 -translate-y-1/2 rounded-2xl border border-border bg-card p-6 shadow-2xl focus:outline-none">
            <div className="flex items-start gap-4">
              <span className="flex size-11 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
                <ShieldCheck className="size-5" aria-hidden="true" />
              </span>
              <div className="min-w-0 flex-1">
                <Dialog.Title className="text-lg font-semibold">Confirmá esta acción sensible</Dialog.Title>
                <Dialog.Description className="mt-2 text-sm leading-6 text-muted-foreground">
                  Ingresá un código nuevo de tu aplicación autenticadora. El comprobante sólo servirá para esta operación.
                </Dialog.Description>
              </div>
              <Dialog.Close asChild>
                <button type="button" className="icon-button -mr-2 -mt-2" aria-label="Cancelar verificación" disabled={busy}>
                  <X className="size-5" />
                </button>
              </Dialog.Close>
            </div>

            <form className="mt-6 space-y-4" onSubmit={(event) => { event.preventDefault(); void verify(); }}>
              <label className="field-group" htmlFor="step-up-code">
                Código TOTP
                <input
                  ref={codeRef}
                  id="step-up-code"
                  className="form-input font-mono tracking-[0.3em]"
                  inputMode="numeric"
                  autoComplete="one-time-code"
                  pattern="[0-9]{6}"
                  maxLength={6}
                  value={code}
                  onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
                  autoFocus
                  disabled={busy}
                  aria-invalid={Boolean(error)}
                  aria-describedby={error ? "step-up-code-error" : undefined}
                />
              </label>
              {error && <p id="step-up-code-error" className="auth-error" role="alert">{error}</p>}
              <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
                <Boton type="button" className="page-button-secondary" onClick={close} disabled={busy}>Cancelar</Boton>
                <Boton type="submit" disabled={busy || code.length !== 6}>
                  {busy ? "Verificando…" : "Verificar y continuar"}
                </Boton>
              </div>
            </form>
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>
    </StepUpContext.Provider>
  );
};
