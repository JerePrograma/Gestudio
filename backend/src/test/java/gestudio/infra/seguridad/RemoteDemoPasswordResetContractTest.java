package gestudio.infra.seguridad;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

class RemoteDemoPasswordResetContractTest {

    private final Path root = Path.of(System.getProperty("user.dir"))
            .toAbsolutePath()
            .normalize()
            .getParent();

    @Test
    void launcherExponeRestablecimientoConUsuarioExplicito() throws IOException {
        String launcher = Files.readString(root.resolve("scripts/demo-remote.ps1"));

        assertThat(launcher)
                .contains(
                        "ValidateSet(\"Start\", \"Status\", \"Stop\", \"Reset\", \"ResetPassword\")",
                        "[string] $Username = \"\"",
                        "ResetPassword exige -Username",
                        "Reset-DemoPassword -Username"
                );
    }

    @Test
    void restablecimientoUsaJdk21BcryptRevocaSesionesYAudita() throws IOException {
        String credentials = Files.readString(root.resolve("scripts/remote-demo/credentials.ps1"));

        assertThat(credentials)
                .contains(
                        "function Reset-DemoPassword",
                        "function Resolve-Java21",
                        "Get-Command javac",
                        "$env:ProgramFiles\\Microsoft",
                        "Initialize-BcryptHelper",
                        "Invoke-BcryptHelper",
                        "auth_version = COALESCE(u.auth_version, 0) + 1",
                        "UPDATE public.refresh_sessions",
                        "DEMO_PASSWORD_RESET_LOCAL",
                        "INSERT INTO public.auditoria_eventos",
                        "CASE WHEN u.activo THEN '1' ELSE '0' END",
                        "Assert-Equal $parts[3] \"1\""
                )
                .doesNotContain(
                        "Write-Host $plain",
                        "Write-Host $passwordHash",
                        "Assert-Equal $parts[3] \"t\""
                );
    }
}
