import { BrowserRouter } from "react-router-dom";
import { QueryClientProvider } from "@tanstack/react-query";
import { ToastContainer } from "react-toastify";
import { queryClient } from "./hooks/queryClient";
import AppRouter from "./rutas/AppRouter";
import { AuthProvider } from "./hooks/context/authContext";
import { SidebarProvider } from "./hooks/context/SideBarContext";

const App = () => (
  <QueryClientProvider client={queryClient}>
    <BrowserRouter>
      <AuthProvider>
        <SidebarProvider>
          <AppRouter />
          <ToastContainer />
        </SidebarProvider>
      </AuthProvider>
    </BrowserRouter>
  </QueryClientProvider>
);

export default App;
