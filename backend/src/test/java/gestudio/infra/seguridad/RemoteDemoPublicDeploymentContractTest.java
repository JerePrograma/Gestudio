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
    void despliegueEsperaConexionDnsYBackendAntesDePublicarPages() throws IOException {
        String script = Files.readString(root.resolve("scripts/deploy-remote-demo-public.ps1"));

        assertThat(script)
                .contains(
                        "Registered tunnel connection",
                        "Wait-DnsResolution",
                        "--protocol", "http2",
                        "Protección directa del túnel",
                        "Quick Tunnel hacia backend",
                        "pages", "secret", "bulk",
                        "pages", "deploy", "dist",
                        "Refresh público",
                        "sin 530/1016",
                        "CORS público"
                );
    }

    @Test
    void refreshPublicoReproduceElOriginDelNavegador() throws IOException {
        String script = Files.readString(root.resolve("scripts/deploy-remote-demo-public.ps1"));

        assertThat(script)
                .contains(
                        "$refreshCheck = @{",
                        "Uri = \"$pagesOriginNormalized/api/login/refresh\"",
                        "Method = \"POST\"",
                        "Headers = @{ \"Origin\" = $pagesOriginNormalized }",
                        "ExpectedStatuses = @(401)"
                )
                .doesNotContain("ExpectedStatuses = @(401, 403)");
    }

    @Test
    void despliegueSoloDetieneTunelesRegistradosPorGestudio() throws IOException {
        String script = Files.readString(root.resolve("scripts/deploy-remote-demo-public.ps1"));

        assertThat(script)
                .contains(
                        "public-deployment.json",
                        "quick-tunnel.json",
                        "Get-CimInstance Win32_Process",
                        "$commandLine.Contains(",
                        "Stop-Process -Id $trackedProcessId",
                        "no corresponde al Quick Tunnel de Gestudio; no se detuvo"
                )
                .doesNotContain(
                        "Stop-Process -Name",
                        "taskkill",
                        "Get-Process cloudflared | Stop-Process"
                );
    }

    @Test
    void despliegueExigeMainLimpiaYNoUsaContinuacionesDeShellUnix() throws IOException {
        String script = Files.readString(root.resolve("scripts/deploy-remote-demo-public.ps1"));

        assertThat(script)
                .contains(
                        "La rama actual debe ser main",
                        "status", "--porcelain=v1",
                        "fetch", "origin", "--prune",
                        "main local no coincide con origin/main",
                        "$startArguments = @{",
                        "$frontendCheck = @{"
                )
                .doesNotContain(
                        "Start-Process \\",
                        "Wait-HttpStatus \\",
                        "Write-TunnelState \\"
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
