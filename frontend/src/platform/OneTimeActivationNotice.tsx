import { Copy, X } from "lucide-react";
import Boton from "../componentes/comunes/Boton";
import { platformActivationUrl } from "./activationLink";
import type { ActivationDelivery } from "./platformTypes";

interface OneTimeActivationNoticeProps {
  activation: ActivationDelivery;
  onDismiss: () => void;
}

const OneTimeActivationNotice = ({ activation, onDismiss }: OneTimeActivationNoticeProps) => {
  const activationUrl = platformActivationUrl(activation.token);
  return (
    <section
      className="rounded-[var(--radius-lg)] border border-[hsl(var(--warning)/0.3)] bg-[hsl(var(--warning-soft))] p-4"
      aria-labelledby="membership-activation-title"
    >
      <div className="flex items-start gap-3">
        <div className="min-w-0 flex-1">
          <h2 id="membership-activation-title" className="text-base font-semibold text-[hsl(var(--warning))]">
            Activación de identidad: se muestra una sola vez
          </h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Entregá este enlace por un canal externo seguro. El fragmento no se envía al servidor y no vuelve a exponerse en un reintento.
          </p>
          <div className="mt-3 flex flex-col gap-2 sm:flex-row">
            <code className="min-w-0 flex-1 break-all rounded-lg bg-card p-3 text-xs">
              {activationUrl}
            </code>
            <Boton
              className="page-button-secondary"
              onClick={() => void navigator.clipboard.writeText(activationUrl)}
            >
              <Copy className="size-4" /> Copiar
            </Boton>
          </div>
          <p className="mt-2 text-xs text-muted-foreground">
            Vence: {new Date(activation.expiresAt).toLocaleString()}
          </p>
        </div>
        <button
          type="button"
          className="icon-button"
          aria-label="Descartar token de activación"
          onClick={onDismiss}
        >
          <X className="size-4" />
        </button>
      </div>
    </section>
  );
};

export default OneTimeActivationNotice;
