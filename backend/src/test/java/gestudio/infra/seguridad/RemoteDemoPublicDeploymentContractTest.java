package gestudio.infra.seguridad;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

class RemoteDemoPublicDeploymentContractTest {

    private final Path root = Path.of(System.getProperty("user.dir"))
            .toAbsolutePath()
            .normalize()
            .getParent();

    @Test
    void publicadorUsaLaDemoMultitenantPersistenteYElProyectoPagesExistente() throws IOException {
        String script = Files.readString(root.resolve("scripts/deploy-remote-demo-public.ps1"));

        assertThat(script)
                .contains(
                        "demo-local-multitenant.ps1",
                        "-PublicOrigin",
                        "-RotatePublicCredential",
                        "STATUS: PASS",
                        "Registered tunnel connection",
                        "Wait-DnsResolution",
                        "--protocol", "http2",
                        "pages", "secret", "bulk",
                        "pages", "deploy", "dist",
                        "gestudio-demo-jere-287b8c90",
                        "--commit-dirty=true"
                )
                .doesNotContain(
                        "demo-remote.ps1",
                        ".env.remote-demo",
                        "gestudio-remote-demo"
                );
    }

    @Test
    void certificacionPublicaCubreSesionCookieTenantYAislamiento() throws IOException {
        String script = Files.readString(root.resolve("scripts/deploy-remote-demo-public.ps1"));

        assertThat(script)
                .contains(
                        "alpha.demo.presentacion",
                        "DEMO_COMERCIAL",
                        "Escuela Danza Marcos Paz",
                        "Beta E2E d3a010ca1001",
                        "/api/login/refresh",
                        "/api/login/logout",
                        "SameSite=Strict",
                        "Path=/api/login",
                        "Refresh posterior a logout",
                        "/api/platform/me",
                        "/actuator/health/readiness"
                );
    }

    @Test
    void proxyTokenYHostnameDelTunnelSeMantienenRedactadosYFueraDeGit() throws IOException {
        String script = Files.readString(root.resolve("scripts/deploy-remote-demo-public.ps1"));

        assertThat(script)
                .contains(
                        "public-deployment.json",
                        "credentials.json",
                        "Assert-SecretsOutsideGit",
                        "GESTUDIO_BACKEND_ORIGIN",
                        "GESTUDIO_PROXY_TOKEN",
                        "QUICK_TUNNEL_REDACTED",
                        "Get-CimInstance Win32_Process",
                        "ProcessStartedAt",
                        "ExecutablePath",
                        "Stop-Process -Id $process.Id"
                )
                .doesNotContain(
                        "Stop-Process -Name",
                        "taskkill",
                        "Get-Process cloudflared | Stop-Process",
                        "Write-Host \"Quick Tunnel:"
                );
    }

    @Test
    void despliegueExigeMainSinDescartarUnWorktreeSucio() throws IOException {
        String script = Files.readString(root.resolve("scripts/deploy-remote-demo-public.ps1"));

        assertThat(script)
                .contains(
                        "La rama actual debe ser main",
                        "origin/main",
                        "diff", "--check",
                        "status", "--porcelain=v1",
                        "fetch", "origin", "--prune",
                        "el worktree actual se conserva"
                )
                .doesNotContain(
                        "git reset --hard",
                        "git checkout --",
                        "Existen cambios locales versionables"
                );
    }

    @Test
    void launcherHumanoDelegaAccionesSinExigirElEnvLegacy() throws IOException {
        String launcher = Files.readString(root.resolve("DESPLEGAR-DEMO-REMOTA.cmd"));

        assertThat(launcher)
                .contains(
                        "deploy-remote-demo-public.ps1",
                        "-RepoPath \"%REPO_ROOT%\" %*"
                )
                .doesNotContain(
                        ".env.remote-demo",
                        "demo-remote.ps1"
                );
    }

    @Test
    void ocultamientoDirectoNoDisparaElEndpointDeError() throws IOException {
        String filter = Files.readString(root.resolve(
                "backend/src/main/java/gestudio/infra/seguridad/RemoteDemoProxyTokenFilter.java"));

        assertThat(filter)
                .contains(
                        "response.setStatus(HttpServletResponse.SC_NOT_FOUND)",
                        "response.setContentLength(0)"
                )
                .doesNotContain("response.sendError");
    }
}
