"use client";

import type { ReactNode } from "react";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
  TableFooter,
} from "../ui/table";
import EmptyState from "./EmptyState";

interface TablaProps<T extends object> {
  headers: string[];
  data: T[];
  getRowKey: (row: T) => React.Key;
  actions?: (row: T) => ReactNode;
  customRender?: (row: T) => (string | number | ReactNode)[];
  footer?: ReactNode;
  emptyMessage?: string;
  className?: string;
}

const Tabla = <T extends object>({
  headers,
  data,
  getRowKey,
  actions,
  customRender,
  footer,
  emptyMessage = "No hay datos disponibles",
  className = "",
}: TablaProps<T>) => {
  if (data.length === 0) {
    return <EmptyState message={emptyMessage} />;
  }

  return (
    <div className={`w-full ${className}`}>
      {/* Versión para pantallas medianas y grandes */}
      <div className="data-table-shell hidden sm:block">
        <Table>
          <TableHeader className="sticky top-0 z-10 bg-muted/95 backdrop-blur-sm">
            <TableRow className="hover:bg-transparent">
              {headers.map((header, idx) => (
                <TableHead
                  key={`${header}-${idx}`}
                  className="h-11 whitespace-nowrap px-4 text-left text-xs font-bold uppercase tracking-[0.06em] text-muted-foreground"
                >
                  {header}
                </TableHead>
              ))}
              {actions && (
                <TableHead className="h-11 whitespace-nowrap px-4 text-right text-xs font-bold uppercase tracking-[0.06em] text-muted-foreground">
                  Acciones
                </TableHead>
              )}
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.map((row) => {
                const cells = customRender ? customRender(row) : Object.values(row);
                return (
                <TableRow
                  key={getRowKey(row)}
                  className="group border-b border-border/70 transition-colors hover:bg-muted/45"
                >
                  {cells.map((value, idx) => (
                        <TableCell
                          key={idx}
                          className="whitespace-nowrap px-4 py-3"
                        >
                          {typeof value === "object" ? value : String(value)}
                        </TableCell>
                      ))}
                  {actions && (
                    <TableCell className="whitespace-nowrap px-3 py-2 text-right">
                      <div className="row-actions">
                        {actions(row)}
                      </div>
                    </TableCell>
                  )}
                </TableRow>
              )})}
          </TableBody>
          {footer && <TableFooter>{footer}</TableFooter>}
        </Table>
      </div>

      {/* Versión para móviles (cards en lugar de tabla) */}
      <div className="space-y-3 sm:hidden">
        {data.map((row) => {
            const cells = customRender ? customRender(row) : Object.values(row);
            return (
            <article key={getRowKey(row)} className="section-card space-y-3">
              {headers.map((header, headerIndex) => {
                const value = cells[headerIndex];
                return (
                  <div
                    key={`${header}-${headerIndex}`}
                    className="grid grid-cols-[minmax(7rem,0.8fr)_1fr] items-start gap-3 border-b border-border/60 pb-2 last:border-0 last:pb-0"
                  >
                    <span className="text-xs font-bold uppercase tracking-wide text-muted-foreground">
                      {header}
                    </span>
                    <div className="min-w-0 text-right text-sm font-medium">
                      {typeof value === "object" ? (
                        value
                      ) : (
                        <span className="text-sm">{String(value)}</span>
                      )}
                    </div>
                  </div>
                );
              })}
              {actions && (
                <div className="flex items-center justify-between border-t border-border pt-3">
                  <span className="text-xs font-bold uppercase tracking-wide text-muted-foreground">Acciones</span>
                  <div className="row-actions">
                    {actions(row)}
                  </div>
                </div>
              )}
            </article>
          )})}
      </div>
    </div>
  );
};

export default Tabla;
