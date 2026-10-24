type PublicDemoEnvironment = Pick<
  ImportMetaEnv,
  "VITE_PUBLIC_DEMO_ENABLED" | "VITE_PUBLIC_DEMO_USERNAME" | "VITE_PUBLIC_DEMO_PASSWORD"
>;

// Vite embeds these values in the browser bundle. Only use the synthetic
// presentation account; never configure an operator or infrastructure secret.
export function publicDemoCredentials(environment: PublicDemoEnvironment = import.meta.env) {
  const nombreUsuario = environment.VITE_PUBLIC_DEMO_USERNAME?.trim();
  const contrasena = environment.VITE_PUBLIC_DEMO_PASSWORD;

  return environment.VITE_PUBLIC_DEMO_ENABLED === "true" && nombreUsuario && contrasena
    ? { nombreUsuario, contrasena }
    : null;
}
