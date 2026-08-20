import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, type RenderResult } from "@testing-library/react";
import type { ReactElement } from "react";
import { MemoryRouter, Route, Routes } from "react-router";

export const renderPlatformPage = (
  element: ReactElement,
  path = "/platform/test",
  route = "/platform/test",
): RenderResult & { queryClient: QueryClient } => {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false, gcTime: 0 } },
  });
  const result = render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[path]}>
        <Routes>
          <Route path={route} element={element} />
          <Route path="/platform/tenants" element={<p>Listado destino</p>} />
          <Route path="/platform/tenants/new" element={<p>Alta destino</p>} />
          <Route path="/platform/tenants/:tenantId" element={<p>Detalle destino</p>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
  return Object.assign(result, { queryClient });
};
