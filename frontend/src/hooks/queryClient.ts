import { QueryClient } from "@tanstack/react-query";
import { errorCategory } from "../api/apiError";

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: false,
      retry: (failureCount, error) =>
        failureCount < 2 && ["internal", "unknown"].includes(errorCategory(error)),
      staleTime: 1000 * 60 * 5,
    },
  },
});

let requestScope = new AbortController();

export const tenantRequestSignal = (): AbortSignal => requestScope.signal;

export async function resetTenantClientState(): Promise<void> {
  requestScope.abort();
  requestScope = new AbortController();
  await queryClient.cancelQueries();
  queryClient.clear();
}
