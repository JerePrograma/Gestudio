import { CheckCircle2, Copy, KeyRound, ShieldCheck } from "lucide-react";
import {
  useEffect,
  useLayoutEffect,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import { Link, useLocation, useNavigate } from "react-router";
import { getApiError, getApiErrorMessage } from "../../api/apiError";
import Boton from "../../componentes/comunes/Boton";
import { activationTokenFromHash } from "../activationLink";
import { platformApi } from "../platformApi";

type ActivationMode = "IDENTITY" | "PLATFORM_MFA";
type ActivationErrorTarget =
  | "activation-password"
  | "activation-confirm-password"
  | "activation-totp-secret"
  | "activation-totp-code"
  | null;

const PlatformActivatePage = () => {
  const location = useLocation();
  const navigate = useNavigate();
  const [token] = useState(() => activationTokenFromHash(location.hash));
  const [mode, setMode] = useState<ActivationMode>("PLATFORM_MFA");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [totpSecret, setTotpSecret] = useState("");
  const [totpCode, setTotpCode] = useState("");
  const [recoveryCodes, setRecoveryCodes] = useState<string[] | null>(null);
  const [completedIdentity, setCompletedIdentity] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [errorTarget, setErrorTarget] = useState<ActivationErrorTarget>(null);

  const showFieldError = (
    message: string,
    target: Exclude<ActivationErrorTarget, null>,
  ) => {
    setError(message);
    setErrorTarget(target);
    document.getElementById(target)?.focus();
  };

  const clearFieldError = (target: Exclude<ActivationErrorTarget, null>) => {
    if (errorTarget !== target) return;
    setError("");
    setErrorTarget(null);
  };

  useLayoutEffect(() => {
    if (location.hash || location.search) {
      window.history.replaceState(
        window.history.state,
        "",
        "/platform/activate",
      );
    }
  }, [location.hash, location.search]);

  useEffect(() => {
    if (location.hash || location.search) {
      navigate("/platform/activate", { replace: true });
    }
  }, [location.hash, location.search, navigate]);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setError("");
    setErrorTarget(null);
    if (!token) {
      setError("El enlace no contiene un token de activación.");
      return;
    }
    if (password && password !== confirmPassword) {
      showFieldError(
        "Las contraseñas no coinciden.",
        "activation-confirm-password",
      );
      return;
    }
    if (mode === "IDENTITY" && !password) {
      showFieldError(
        "Ingresá y confirmá una contraseña nueva.",
        "activation-password",
      );
      return;
    }
    if (
      mode === "PLATFORM_MFA" &&
      (!totpSecret.trim() || !/^\d{6}$/.test(totpCode))
    ) {
      showFieldError(
        "Ingresá el secreto Base32 y el código TOTP actual de 6 dígitos.",
        !totpSecret.trim() ? "activation-totp-secret" : "activation-totp-code",
      );
      return;
    }

    setBusy(true);
    try {
      const result = await platformApi.activateIdentity({
        token,
        ...(password ? { password } : {}),
        ...(mode === "PLATFORM_MFA"
          ? {
              totpSecret: totpSecret.trim().replace(/[\s-]/g, "").toUpperCase(),
              totpCode,
            }
          : {}),
      });
      setPassword("");
      setConfirmPassword("");
      setTotpSecret("");
      setTotpCode("");
      if (result.recoveryCodes.length > 0)
        setRecoveryCodes(result.recoveryCodes);
      else setCompletedIdentity(true);
    } catch (activationError) {
      setErrorTarget(null);
      const apiError = getApiError(activationError);
      if (mode === "IDENTITY" && apiError?.status === 400) {
        setError(
          `${apiError.message} Si este enlace es para acceso de plataforma, seleccioná “Configurar MFA”.`,
        );
      } else {
        setError(
          getApiErrorMessage(
            activationError,
            "No se pudo completar la activación. El enlace puede haber vencido o ya fue usado.",
          ),
        );
      }
    } finally {
      setBusy(false);
    }
  };

  if (completedIdentity) {
    return (
      <main className="auth-page">
        <section className="w-full max-w-lg rounded-2xl border border-border bg-card p-6 text-center shadow-xl sm:p-10">
          <span className="mx-auto flex size-14 items-center justify-center rounded-2xl bg-[hsl(var(--success-soft))] text-[hsl(var(--success))]">
            <CheckCircle2 className="size-7" />
          </span>
          <h1 className="mt-5 text-2xl font-bold">Identidad activada</h1>
          <p className="mt-2 text-sm leading-6 text-muted-foreground">
            La contraseña quedó configurada. Ya podés ingresar a la organización
            que te fue asignada.
          </p>
          <Link className="button-base page-button mt-6" to="/login">
            Ir al inicio de sesión
          </Link>
        </section>
      </main>
    );
  }

  if (recoveryCodes) {
    return (
      <main className="auth-page">
        <section className="w-full max-w-2xl rounded-2xl border border-border bg-card p-6 shadow-xl sm:p-10">
          <div className="flex items-start gap-4">
            <span className="flex size-12 shrink-0 items-center justify-center rounded-xl bg-[hsl(var(--success-soft))] text-[hsl(var(--success))]">
              <ShieldCheck className="size-6" />
            </span>
            <div>
              <h1 className="text-2xl font-bold">
                Acceso de plataforma activado
              </h1>
              <p className="mt-2 text-sm leading-6 text-muted-foreground">
                Guardá estos códigos ahora. Se muestran una sola vez y cada uno
                sirve para una única recuperación.
              </p>
            </div>
          </div>
          <ol className="mt-6 grid gap-2 rounded-xl border border-border bg-muted/40 p-4 sm:grid-cols-2">
            {recoveryCodes.map((code, index) => (
              <li key={index}>
                <code className="block rounded bg-card px-3 py-2 text-center text-sm font-semibold">
                  {code}
                </code>
              </li>
            ))}
          </ol>
          <div className="mt-6 flex flex-col gap-2 sm:flex-row sm:justify-end">
            <Boton
              className="page-button-secondary"
              onClick={() =>
                void navigator.clipboard.writeText(recoveryCodes.join("\n"))
              }
            >
              <Copy className="size-4" /> Copiar códigos
            </Boton>
            <Link className="button-base page-button" to="/platform/login">
              Ya los guardé
            </Link>
          </div>
        </section>
      </main>
    );
  }

  return (
    <main className="auth-page">
      <section className="w-full max-w-2xl rounded-2xl border border-border bg-card p-6 shadow-xl sm:p-10">
        <div className="flex items-start gap-4">
          <span className="flex size-12 shrink-0 items-center justify-center rounded-xl bg-primary text-primary-foreground">
            <KeyRound className="size-6" />
          </span>
          <div>
            <p className="page-eyebrow">Activación segura</p>
            <h1 className="mt-1 text-2xl font-bold">Completar configuración</h1>
            <p className="mt-2 text-sm leading-6 text-muted-foreground">
              El token se mantiene sólo durante esta pantalla y fue retirado de
              la barra de direcciones.
            </p>
          </div>
        </div>

        <form
          className="mt-7 space-y-5"
          onSubmit={(event) => void submit(event)}
          noValidate
        >
          <fieldset>
            <legend className="mb-2 text-sm font-semibold">
              Tipo de activación
            </legend>
            <div className="grid gap-2 sm:grid-cols-2">
              <label className="checkbox-field items-center">
                <input
                  type="radio"
                  name="activation-mode"
                  checked={mode === "PLATFORM_MFA"}
                  onChange={() => {
                    setMode("PLATFORM_MFA");
                    setError("");
                    setErrorTarget(null);
                  }}
                />{" "}
                Configurar MFA de plataforma
              </label>
              <label className="checkbox-field items-center">
                <input
                  type="radio"
                  name="activation-mode"
                  checked={mode === "IDENTITY"}
                  onChange={() => {
                    setMode("IDENTITY");
                    setError("");
                    setErrorTarget(null);
                  }}
                />{" "}
                Activar identidad tenant
              </label>
            </div>
          </fieldset>

          <div className="form-grid">
            <div className="field-group">
              <label htmlFor="activation-password">
                {mode === "IDENTITY"
                  ? "Contraseña nueva"
                  : "Contraseña nueva (opcional)"}
              </label>
              <input
                id="activation-password"
                className="form-input"
                type="password"
                autoComplete="new-password"
                minLength={mode === "IDENTITY" ? 12 : 16}
                maxLength={72}
                value={password}
                onChange={(event) => {
                  setPassword(event.target.value);
                  clearFieldError("activation-password");
                }}
                aria-invalid={errorTarget === "activation-password"}
                aria-describedby={
                  errorTarget === "activation-password"
                    ? "activation-form-error"
                    : undefined
                }
              />
              <span className="form-help">
                {mode === "IDENTITY"
                  ? "Entre 12 y 72 bytes UTF-8."
                  : "Dejala vacía para conservar la contraseña de una identidad ya activa."}
              </span>
            </div>
            <label
              className="field-group"
              htmlFor="activation-confirm-password"
            >
              Confirmar contraseña
              <input
                id="activation-confirm-password"
                className="form-input"
                type="password"
                autoComplete="new-password"
                maxLength={72}
                value={confirmPassword}
                onChange={(event) => {
                  setConfirmPassword(event.target.value);
                  clearFieldError("activation-confirm-password");
                }}
                disabled={!password}
                aria-invalid={errorTarget === "activation-confirm-password"}
                aria-describedby={
                  errorTarget === "activation-confirm-password"
                    ? "activation-form-error"
                    : undefined
                }
              />
            </label>
          </div>

          {mode === "PLATFORM_MFA" && (
            <SectionCardLike>
              <p className="text-sm font-semibold">Aplicación autenticadora</p>
              <p className="mt-1 text-sm leading-6 text-muted-foreground">
                Generá un secreto Base32 de al menos 20 bytes en un canal
                autorizado, cargalo en tu aplicación TOTP e ingresá el código
                actual.
              </p>
              <div className="form-grid mt-4">
                <label className="field-group" htmlFor="activation-totp-secret">
                  Secreto Base32
                  <input
                    id="activation-totp-secret"
                    className="form-input font-mono"
                    autoComplete="off"
                    maxLength={128}
                    value={totpSecret}
                    onChange={(event) => {
                      setTotpSecret(event.target.value);
                      clearFieldError("activation-totp-secret");
                    }}
                    aria-invalid={errorTarget === "activation-totp-secret"}
                    aria-describedby={
                      errorTarget === "activation-totp-secret"
                        ? "activation-form-error"
                        : undefined
                    }
                  />
                </label>
                <label className="field-group" htmlFor="activation-totp-code">
                  Código TOTP
                  <input
                    id="activation-totp-code"
                    className="form-input font-mono tracking-[0.25em]"
                    inputMode="numeric"
                    autoComplete="one-time-code"
                    maxLength={6}
                    pattern="[0-9]{6}"
                    value={totpCode}
                    onChange={(event) => {
                      setTotpCode(
                        event.target.value.replace(/\D/g, "").slice(0, 6),
                      );
                      clearFieldError("activation-totp-code");
                    }}
                    aria-invalid={errorTarget === "activation-totp-code"}
                    aria-describedby={
                      errorTarget === "activation-totp-code"
                        ? "activation-form-error"
                        : undefined
                    }
                  />
                </label>
              </div>
            </SectionCardLike>
          )}

          {!token && (
            <p className="auth-error" role="alert">
              El enlace no contiene un token de activación.
            </p>
          )}
          {error && (
            <p
              id="activation-form-error"
              className="rounded-lg border border-destructive/20 bg-destructive/10 p-3 text-sm font-medium text-destructive"
              role="alert"
            >
              {error}
            </p>
          )}
          <div className="form-actions">
            <Boton type="submit" disabled={busy || !token}>
              {busy ? "Activando…" : "Completar activación"}
            </Boton>
          </div>
        </form>
      </section>
    </main>
  );
};

const SectionCardLike = ({ children }: { children: ReactNode }) => (
  <section className="rounded-xl border border-border bg-muted/30 p-4">
    {children}
  </section>
);

export default PlatformActivatePage;
