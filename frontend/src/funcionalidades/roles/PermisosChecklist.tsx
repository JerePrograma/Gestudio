import type { PermisoResponse } from "../../types/types";

interface Props {
  permisos: PermisoResponse[];
  seleccionados: string[];
  onChange: (codigos: string[]) => void;
  disabled?: boolean;
}

const PermisosChecklist = ({ permisos, seleccionados, onChange, disabled = false }: Props) => {
  const porModulo = permisos.reduce<Record<string, PermisoResponse[]>>((grupos, permiso) => {
    (grupos[permiso.modulo] ??= []).push(permiso);
    return grupos;
  }, {});
  const toggle = (codigo: string, checked: boolean) => onChange(
    checked
      ? [...new Set([...seleccionados, codigo])].sort()
      : seleccionados.filter((value) => value !== codigo),
  );

  return (
    <div className="grid gap-4 md:grid-cols-2">
      {Object.entries(porModulo).map(([modulo, items]) => (
        <fieldset key={modulo} className="page-card space-y-2 p-4" disabled={disabled}>
          <legend className="font-semibold">{modulo}</legend>
          {items?.map((permiso) => (
            <label key={permiso.codigo} className="flex items-start gap-2 text-sm">
              <input
                type="checkbox"
                checked={seleccionados.includes(permiso.codigo)}
                onChange={(event) => toggle(permiso.codigo, event.target.checked)}
              />
              <span><strong>{permiso.codigo}</strong><br />{permiso.descripcion}</span>
            </label>
          ))}
        </fieldset>
      ))}
    </div>
  );
};

export default PermisosChecklist;
