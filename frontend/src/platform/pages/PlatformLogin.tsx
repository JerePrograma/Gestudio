import { ErrorMessage, Field, Form, Formik, useFormikContext } from "formik";
import { KeyRound, ShieldCheck } from "lucide-react";
import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router";
import * as yup from "yup";
import { getApiErrorMessage } from "../../api/apiError";
import Boton from "../../componentes/comunes/Boton";
import { useAuth } from "../../hooks/context/useAuth";
import type { PlatformMfaMethod } from "../../hooks/context/auth-context";

interface PlatformLoginValues {
  nombreUsuario: string;
  contrasena: string;
  metodo: PlatformMfaMethod;
  codigo: string;
}

const platformLoginSchema = yup.object({
  nombreUsuario: yup.string().trim().max(100, "Máximo 100 caracteres").required("Ingresá tu usuario"),
  contrasena: yup.string().max(72, "Máximo 72 caracteres").required("Ingresá tu contraseña"),
  metodo: yup.mixed<PlatformMfaMethod>().oneOf(["TOTP", "RECOVERY"]).required(),
  codigo: yup.string().when("metodo", {
    is: "TOTP",
    then: (schema) => schema.matches(/^\d{6}$/, "Ingresá los 6 dígitos").required("Ingresá el código TOTP"),
    otherwise: (schema) => schema.trim().min(8, "El código de recuperación es inválido").max(80).required("Ingresá el código de recuperación"),
  }),
});

const FocusFirstLoginError = () => {
  const { errors, isSubmitting, isValidating, submitCount } = useFormikContext<PlatformLoginValues>();
  const { codigo, contrasena, nombreUsuario } = errors;

  useEffect(() => {
    if (submitCount === 0 || isSubmitting || isValidating) return;
    const firstInvalidId = nombreUsuario
      ? "platform-username"
      : contrasena
        ? "platform-password"
        : codigo
          ? "platform-code"
          : null;
    if (firstInvalidId) document.getElementById(firstInvalidId)?.focus();
  }, [codigo, contrasena, isSubmitting, isValidating, nombreUsuario, submitCount]);

  return null;
};

const PlatformLogin = () => {
  const { isAuth, scope, platformLogin } = useAuth();
  const navigate = useNavigate();
  const [error, setError] = useState("");

  useEffect(() => {
    if (isAuth && scope === "PLATFORM") navigate("/platform/tenants", { replace: true });
  }, [isAuth, navigate, scope]);

  const submit = async (values: PlatformLoginValues) => {
    setError("");
    try {
      await platformLogin(
        values.nombreUsuario.trim(),
        values.contrasena,
        values.metodo,
        values.codigo.trim(),
      );
      navigate("/platform/tenants", { replace: true });
    } catch (loginError) {
      setError(getApiErrorMessage(
        loginError,
        "No se pudo validar el acceso de plataforma. Revisá las credenciales y el segundo factor.",
      ));
    }
  };

  return (
    <main className="auth-page">
      <div className="auth-shell">
        <section className="auth-brand" aria-label="Gestudio Control plane">
          <div>
            <span className="auth-brand-mark"><ShieldCheck className="size-6" aria-hidden="true" /></span>
            <h1 className="auth-brand-title">Administración global con verificación reforzada.</h1>
            <p className="auth-brand-copy">
              Gestioná organizaciones, administradores y auditoría sin convertir una sesión tenant en acceso de plataforma.
            </p>
          </div>
          <p className="text-xs font-semibold uppercase tracking-[0.14em] text-background/55">
            Gestudio · Control plane
          </p>
        </section>

        <section className="auth-card">
          <p className="page-eyebrow">Acceso restringido</p>
          <h2 className="mt-2 text-2xl font-bold sm:text-3xl">Iniciar sesión en plataforma</h2>
          <p className="mb-7 mt-2 text-sm leading-6 text-muted-foreground">
            La contraseña y el segundo factor se verifican juntos. Este acceso no selecciona una organización.
          </p>

          <Formik<PlatformLoginValues>
            initialValues={{ nombreUsuario: "", contrasena: "", metodo: "TOTP", codigo: "" }}
            validationSchema={platformLoginSchema}
            validateOnBlur={false}
            validateOnChange={false}
            onSubmit={submit}
          >
            {({ errors, isSubmitting, setFieldValue, submitCount, touched, values }) => (
              <Form className="formulario" noValidate>
                <FocusFirstLoginError />
                <div className="field-group">
                  <label htmlFor="platform-username">Nombre de usuario</label>
                  <Field
                    id="platform-username"
                    name="nombreUsuario"
                    className="form-input"
                    autoComplete="username"
                    autoFocus
                    aria-invalid={Boolean(errors.nombreUsuario && (touched.nombreUsuario || submitCount > 0))}
                    aria-describedby={errors.nombreUsuario && (touched.nombreUsuario || submitCount > 0) ? "platform-username-error" : undefined}
                  />
                  <ErrorMessage id="platform-username-error" name="nombreUsuario" component="div" className="auth-error" />
                </div>

                <div className="field-group">
                  <label htmlFor="platform-password">Contraseña</label>
                  <Field
                    id="platform-password"
                    name="contrasena"
                    type="password"
                    className="form-input"
                    autoComplete="current-password"
                    aria-invalid={Boolean(errors.contrasena && (touched.contrasena || submitCount > 0))}
                    aria-describedby={errors.contrasena && (touched.contrasena || submitCount > 0) ? "platform-password-error" : undefined}
                  />
                  <ErrorMessage id="platform-password-error" name="contrasena" component="div" className="auth-error" />
                </div>

                <fieldset>
                  <legend className="mb-2 text-sm font-semibold">Segundo factor</legend>
                  <div className="grid grid-cols-2 gap-2">
                    {(["TOTP", "RECOVERY"] as const).map((method) => (
                      <label key={method} className="checkbox-field items-center">
                        <Field
                          type="radio"
                          name="metodo"
                          value={method}
                          onChange={() => {
                            void setFieldValue("metodo", method);
                            void setFieldValue("codigo", "");
                          }}
                        />
                        {method === "TOTP" ? "Aplicación" : "Recuperación"}
                      </label>
                    ))}
                  </div>
                </fieldset>

                <div className="field-group">
                  <label htmlFor="platform-code">
                    {values.metodo === "TOTP" ? "Código TOTP" : "Código de recuperación"}
                  </label>
                  <Field
                    id="platform-code"
                    name="codigo"
                    className={values.metodo === "TOTP" ? "form-input font-mono tracking-[0.25em]" : "form-input font-mono"}
                    inputMode={values.metodo === "TOTP" ? "numeric" : "text"}
                    autoComplete="one-time-code"
                    maxLength={values.metodo === "TOTP" ? 6 : 80}
                    placeholder={values.metodo === "TOTP" ? "000000" : "Código de un solo uso"}
                    aria-invalid={Boolean(errors.codigo && (touched.codigo || submitCount > 0))}
                    aria-describedby={errors.codigo && (touched.codigo || submitCount > 0) ? "platform-code-error" : undefined}
                  />
                  <ErrorMessage id="platform-code-error" name="codigo" component="div" className="auth-error" />
                </div>

                {error && <div className="rounded-lg border border-destructive/20 bg-destructive/10 p-3 text-sm font-medium text-destructive" role="alert">{error}</div>}

                <Boton type="submit" className="w-full" disabled={isSubmitting}>
                  <KeyRound className="size-4" aria-hidden="true" />
                  {isSubmitting ? "Verificando…" : "Acceder al control plane"}
                </Boton>
                <p className="text-center text-sm text-muted-foreground">
                  ¿Necesitás la gestión de una organización?{" "}
                  <Link className="font-semibold text-primary hover:underline" to="/login">Ir al acceso habitual</Link>
                </p>
              </Form>
            )}
          </Formik>
        </section>
      </div>
    </main>
  );
};

export default PlatformLogin;
