import * as Dialog from "@radix-ui/react-dialog";
import { AlertTriangle, X } from "lucide-react";
import Boton from "../componentes/comunes/Boton";

interface ConfirmDialogProps {
  open: boolean;
  title: string;
  description: string;
  confirmLabel: string;
  busy?: boolean;
  danger?: boolean;
  onConfirm: () => void;
  onOpenChange: (open: boolean) => void;
}

const ConfirmDialog = ({
  open,
  title,
  description,
  confirmLabel,
  busy = false,
  danger = false,
  onConfirm,
  onOpenChange,
}: ConfirmDialogProps) => (
  <Dialog.Root open={open} onOpenChange={(nextOpen) => !busy && onOpenChange(nextOpen)}>
    <Dialog.Portal>
      <Dialog.Overlay className="fixed inset-0 z-50 bg-foreground/45 backdrop-blur-sm" />
      <Dialog.Content className="fixed left-1/2 top-1/2 z-50 w-[min(30rem,calc(100vw-2rem))] -translate-x-1/2 -translate-y-1/2 rounded-2xl border border-border bg-card p-6 shadow-2xl focus:outline-none">
        <div className="flex items-start gap-4">
          <span className={danger ? "flex size-11 shrink-0 items-center justify-center rounded-xl bg-destructive/10 text-destructive" : "flex size-11 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary"}>
            <AlertTriangle className="size-5" aria-hidden="true" />
          </span>
          <div className="min-w-0 flex-1">
            <Dialog.Title className="text-lg font-semibold">{title}</Dialog.Title>
            <Dialog.Description className="mt-2 text-sm leading-6 text-muted-foreground">
              {description}
            </Dialog.Description>
          </div>
          <Dialog.Close asChild>
            <button type="button" className="icon-button -mr-2 -mt-2" aria-label="Cerrar confirmación" disabled={busy}>
              <X className="size-5" />
            </button>
          </Dialog.Close>
        </div>
        <div className="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <Boton type="button" className="page-button-secondary" onClick={() => onOpenChange(false)} disabled={busy}>
            Cancelar
          </Boton>
          <Boton type="button" className={danger ? "page-button-danger" : "page-button"} onClick={onConfirm} disabled={busy}>
            {busy ? "Procesando…" : confirmLabel}
          </Boton>
        </div>
      </Dialog.Content>
    </Dialog.Portal>
  </Dialog.Root>
);

export default ConfirmDialog;
