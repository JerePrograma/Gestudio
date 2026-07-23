package gestudio.infra.seguridad;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

class CompleteApiCertificationContractTest {

    private final Path root = Path.of(System.getProperty("user.dir"))
            .toAbsolutePath()
            .normalize()
            .getParent();

    @Test
    void certificacionCombinaInventarioDinamicoCicloRealYDemoPublica() throws IOException {
        String script = Files.readString(root.resolve("scripts/certify-api-complete.ps1"));

        assertThat(script)
                .contains(
                        "SecurityHttpIntegrationTest",
                        "RemoteDemoProxyTokenFilterTest",
                        "RemoteDemoPublicDeploymentContractTest",
                        "scripts/smoke-local.ps1",
                        "Invoke-IsolatedLifecycle",
                        "Invoke-PublicCertification",
                        "CERTIFICACIÓN INTEGRAL"
                );
    }

    @Test
    void credencialPublicaSeSolicitaDeFormaSeguraYNoSePersiste() throws IOException {
        String script = Files.readString(root.resolve("scripts/certify-api-complete.ps1"));

        assertThat(script)
                .contains(
                        "Read-Host \"Contraseña de $Username para la certificación pública\" -AsSecureString",
                        "[Net.NetworkCredential]::new",
                        "$password = $null",
                        "$accessToken = $null",
                        "secretsPersisted = $false"
                )
                .doesNotContain(
                        "[string] $Password",
                        "param([string] $Password",
                        "ConvertFrom-SecureString",
                        "Set-Content $password",
                        "accessToken = $accessToken"
                );
    }

    @Test
    void informeQuedaFueraDelRepositorioYSinCuerposSensibles() throws IOException {
        String script = Files.readString(root.resolve("scripts/certify-api-complete.ps1"));

        assertThat(script)
                .contains(
                        "Gestudio-Certifications",
                        "api-certification-$runId.json",
                        "api-certification-$runId.md",
                        "scenario = $Scenario",
                        "status = $status",
                        "requestId = $responseRequestId"
                )
                .doesNotContain(
                        "responseBody = $raw",
                        "body = $raw",
                        "cookie =",
                        "refreshToken ="
                );
    }

    @Test
    void fasePublicaEsNoDestructivaYValidaSesionReal() throws IOException {
        String script = Files.readString(root.resolve("scripts/certify-api-complete.ps1"));

        assertThat(script)
                .contains(
                        "Login SUPERADMIN",
                        "Rotación refresh",
                        "Perfil autenticado",
                        "Reporte PDF",
                        "Logout",
                        "Refresh revocado",
                        "sin mutaciones de negocio"
                )
                .doesNotContain(
                        "-Scenario \"Crear alumno público\"",
                        "-Scenario \"Registrar pago público\"",
                        "-Scenario \"Eliminar alumno público\""
                );
    }
}
