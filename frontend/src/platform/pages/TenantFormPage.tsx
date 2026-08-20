import { useQuery } from "@tanstack/react-query";
import { ErrorMessage, Field, Form, Formik, useFormikContext } from "formik";
import { CheckCircle2, Copy, Search, ShieldCheck } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Link, useNavigate } from "react-router";
import * as yup from "yup";
import { getApiErrorMessage } from "../../api/apiError";
import Boton from "../../componentes/comunes/Boton";
import PageHeader from "../../componentes/comunes/PageHeader";
import SectionCard from "../../componentes/comunes/SectionCard";
import useDebounce from "../../hooks/useDebounce";
import { platformActivationUrl } from "../activationLink";
import ConfirmDialog from "../ConfirmDialog";
import { newIdempotencyKey, platformApi } from "../platformApi";
import type { CreateTenantRequest, ProvisionedTenantResponse } from "../platformTypes";
import { useStepUp } from "../stepUpContext";

interface TenantFormValues {
  code: string;
  name: string;
  mode: "EXISTING" | "NEW";
  usuarioId: string;
  nombreUsuario: string;
  identityQuery: string;
}

const schema = yup.object({
  code: yup.string().trim().lowercase().matches(/^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$/, "Usá 3 a 50 letras minúsculas, números o guiones").required("Ingresá un código"),
  name: yup.string().trim().max(150, "Máximo 150 caracteres").required("Ingresá un nombre"),
  mode: yup.mixed<TenantFormValues["mode"]>().oneOf(["EXISTING", "NEW"]).required(),
  usuarioId: yup.string().when("mode", { is: "EXISTING", then: (value) => value.required("Seleccioná una identidad existente") }),
  nombreUsuario: yup.string().when("mode", { is: "NEW", then: (value) => value.trim().max(100).required("Ingresá el nombre de usuario inicial") }),
});

const requestFrom = (values: TenantFormValues): CreateTenantRequest => ({
  code: values.code.trim().toLowerCase(),
  name: values.name.trim(),
  initialAdmin: values.mode === "EXISTING"
    ? { mode: "EXISTING", usuarioId: Number(values.usuarioId) }
    : { mode: "NEW", nombreUsuario: values.nombreUsuario.trim() },
});

const FocusFirstFormError = () => {
  const { errors, isSubmitting, isValidating, submitCount, values } = useFormikContext<TenantFormValues>();
  const { code, name, nombreUsuario, usuarioId } = errors;

  useEffect(() => {
    if (submitCount === 0 || isSubmitting || isValidating) return;
    const firstInvalidId = code
      ? "tenant-code"
      : name
        ? "tenant-name"
        : values.mode === "NEW" && nombreUsuario
          ? "initial-username"
          : values.mode === "EXISTING" && usuarioId
            ? "identity-search"
            : null;
    if (firstInvalidId) document.getElementById(firstInvalidId)?.focus();
  }, [code, isSubmitting, isValidating, name, nombreUsuario, submitCount, usuarioId, values.mode]);

  return null;
};

const TenantFormPage = () => {
  const navigate = useNavigate();
  const { executeWithStepUp } = useStepUp();
  const [identityQuery, setIdentityQuery] = useState("");
  const debouncedIdentityQuery = useDebounce(identityQuery, 300);
  const [pending, setPending] = useState<TenantFormValues | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [result, setResult] = useState<ProvisionedTenantResponse | null>(null);
  const attempt = useRef<{ payload: string; key: string } | null>(null);
  const identities = useQuery({
    queryKey: ["PLATFORM", "identities", debouncedIdentityQuery.trim()],
    queryFn: () => platformApi.searchIdentities(debouncedIdentityQuery.trim()),
    enabled: debouncedIdentityQuery.trim().length >= 2,
  });

  const confirm = async () => {
    if (!pending) return;
    const request = requestFrom(pending);
    const payload = JSON.stringify(request);
    if (attempt.current?.payload !== payload) {
      attempt.current = { payload, key: newIdempotencyKey() };
    }
    const idempotencyKey = attempt.current.key;

    setBusy(true);
    setError("");
    try {
      await executeWithStepUp(
        { action: "TENANT_CREATE", targetType: "TENANT", targetId: request.code, idempotencyKey },
        async (headers) => {
          const created = await platformApi.createTenant(request, headers);
          setResult(created);
        },
      );
      setPending(null);
    } catch (creationError) {
      setError(getApiErrorMessage(creationError, "No se pudo crear la organización."));
      setPending(null);
    } finally {
      setBusy(false);
    }
  };

  if (result) {
    const activationUrl = result.activation
      ? platformActivationUrl(result.activation.token)
      : null;

    return (
      <div className="page-container">
        <PageHeader eyebrow="Control plane" title="Organización creada" description="El alta transaccional quedó registrada." />
        <SectionCard>
          <div className="flex items-start gap-4">
            <span className="flex size-11 items-center justify-center rounded-xl bg-[hsl(var(--success-soft))] text-[hsl(var(--success))]">
              <CheckCircle2 className="size-5" aria-hidden="true" />
            </span>
            <div className="min-w-0 flex-1 space-y-2">
              <h2 className="text-lg font-semibold">{result.tenant.name}</h2>
              <p className="text-sm text-muted-foreground">Código: <code>{result.tenant.code}</code></p>
              {result.activation && activationUrl && (
                <div className="mt-4 rounded-xl border border-[hsl(var(--warning)/0.3)] bg-[hsl(var(--warning-soft))] p-4">
                  <p className="font-semibold text-[hsl(var(--warning))]">Enlace de activación: se muestra una sola vez</p>
                  <div className="mt-2 flex flex-col gap-2 sm:flex-row">
                    <code className="min-w-0 flex-1 break-all rounded-lg bg-card p-3 text-xs">{activationUrl}</code>
                    <Boton className="page-button-secondary" onClick={() => void navigator.clipboard.writeText(activationUrl)}>
                      <Copy className="size-4" aria-hidden="true" /> Copiar
                    </Boton>
                  </div>
                  <p className="mt-2 text-xs text-muted-foreground">Vence: {new Date(result.activation.expiresAt).toLocaleString()}</p>
                </div>
              )}
              <div className="page-button-group pt-4">
                <Boton onClick={() => navigate(`/platform/tenants/${result.tenant.id}`)}>Ver organización</Boton>
                <Boton className="page-button-secondary" onClick={() => navigate("/platform/tenants")}>Volver al listado</Boton>
              </div>
            </div>
          </div>
        </SectionCard>
      </div>
    );
  }

  return (
    <div className="page-container">
      <PageHeader eyebrow="Control plane" title="Nueva organización" description="Creá el tenant y su administrador inicial en una única operación idempotente." />
      <Formik<TenantFormValues>
        initialValues={{ code: "", name: "", mode: "NEW", usuarioId: "", nombreUsuario: "", identityQuery: "" }}
        validationSchema={schema}
        validateOnBlur
        validateOnChange={false}
        onSubmit={(values) => setPending(values)}
      >
        {({ errors, setFieldValue, submitCount, touched, values }) => (
          <Form className="form-container" noValidate>
            <FocusFirstFormError />
            <SectionCard title="Datos de la organización" description="El código identifica al tenant y no podrá cambiarse después.">
              <div className="form-grid">
                <div className="field-group">
                  <label htmlFor="tenant-code">Código</label>
                  <Field
                    id="tenant-code"
                    name="code"
                    className="form-input"
                    placeholder="academia-centro"
                    autoFocus
                    aria-invalid={Boolean(errors.code && (touched.code || submitCount > 0))}
                    aria-describedby={errors.code && (touched.code || submitCount > 0) ? "tenant-code-error" : undefined}
                  />
                  <ErrorMessage id="tenant-code-error" name="code" component="span" className="form-error" />
                </div>
                <div className="field-group">
                  <label htmlFor="tenant-name">Nombre</label>
                  <Field
                    id="tenant-name"
                    name="name"
                    className="form-input"
                    placeholder="Academia Centro"
                    aria-invalid={Boolean(errors.name && (touched.name || submitCount > 0))}
                    aria-describedby={errors.name && (touched.name || submitCount > 0) ? "tenant-name-error" : undefined}
                  />
                  <ErrorMessage id="tenant-name-error" name="name" component="span" className="form-error" />
                </div>
              </div>
            </SectionCard>

            <SectionCard title="Administrador tenant inicial" description="Recibirá el rol ADMINISTRADOR del tenant; nunca privilegio de plataforma.">
              <fieldset>
                <legend className="sr-only">Origen de la identidad</legend>
                <div className="mb-4 grid gap-2 sm:grid-cols-2">
                  <label className="checkbox-field items-center">
                    <Field type="radio" name="mode" value="NEW" /> Crear identidad nueva
                  </label>
                  <label className="checkbox-field items-center">
                    <Field type="radio" name="mode" value="EXISTING" /> Vincular identidad existente
                  </label>
                </div>
              </fieldset>

              {values.mode === "NEW" ? (
                <div className="field-group">
                  <label htmlFor="initial-username">Nombre de usuario</label>
                  <Field
                    id="initial-username"
                    name="nombreUsuario"
                    className="form-input"
                    autoComplete="off"
                    aria-invalid={Boolean(errors.nombreUsuario && (touched.nombreUsuario || submitCount > 0))}
                    aria-describedby={errors.nombreUsuario && (touched.nombreUsuario || submitCount > 0) ? "initial-username-error" : undefined}
                  />
                  <ErrorMessage id="initial-username-error" name="nombreUsuario" component="span" className="form-error" />
                </div>
              ) : (
                <div className="space-y-3">
                  <label className="field-group" htmlFor="identity-search">Buscar identidad global
                    <span className="relative">
                      <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" />
                      <input
                        id="identity-search"
                        className="form-input pl-10"
                        value={identityQuery}
                        onChange={(event) => setIdentityQuery(event.target.value)}
                        placeholder="Escribí al menos 2 caracteres"
                        aria-invalid={Boolean(errors.usuarioId && (touched.usuarioId || submitCount > 0))}
                        aria-describedby={errors.usuarioId && (touched.usuarioId || submitCount > 0) ? "initial-identity-error" : undefined}
                      />
                    </span>
                  </label>
                  {identities.isFetching && <p className="text-sm text-muted-foreground" role="status">Buscando identidades…</p>}
                  {identities.data && identities.data.length > 0 && (
                    <div className="grid gap-2" role="listbox" aria-label="Identidades encontradas">
                      {identities.data.map((identity) => (
                        <button
                          key={identity.id}
                          type="button"
                          className={values.usuarioId === String(identity.id) ? "flex items-center justify-between rounded-lg border border-primary bg-primary/10 p-3 text-left" : "flex items-center justify-between rounded-lg border border-border p-3 text-left hover:bg-muted"}
                          onClick={() => void setFieldValue("usuarioId", String(identity.id))}
                          role="option"
                          aria-selected={values.usuarioId === String(identity.id)}
                        >
                          <span className="font-medium">{identity.nombreUsuario}</span><span className="text-xs text-muted-foreground">ID {identity.id}</span>
                        </button>
                      ))}
                    </div>
                  )}
                  <ErrorMessage id="initial-identity-error" name="usuarioId" component="span" className="form-error" />
                </div>
              )}
            </SectionCard>

            {error && <div className="rounded-lg border border-destructive/20 bg-destructive/10 p-3 text-sm font-medium text-destructive" role="alert">{error}</div>}
            <div className="form-actions">
              <Link className="button-base page-button-secondary" to="/platform/tenants">Cancelar</Link>
              <Boton type="submit" disabled={busy}><ShieldCheck className="size-4" aria-hidden="true" /> Revisar y crear</Boton>
            </div>
          </Form>
        )}
      </Formik>

      <ConfirmDialog
        open={pending !== null}
        title="Crear organización"
        description={pending ? `Se creará “${pending.name}” y su administrador tenant inicial. La operación quedará auditada.` : ""}
        confirmLabel="Crear organización"
        busy={busy}
        onOpenChange={(open) => !open && setPending(null)}
        onConfirm={() => void confirm()}
      />
    </div>
  );
};

export default TenantFormPage;
