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
