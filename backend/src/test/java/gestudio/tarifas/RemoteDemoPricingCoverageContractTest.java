package gestudio.tarifas;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

class RemoteDemoPricingCoverageContractTest {

    private final Path root = Path.of(System.getProperty("user.dir"))
            .toAbsolutePath()
            .normalize()
            .getParent();

    @Test
    void launcherExponeReparacionTarifariaExplicita() throws IOException {
        String launcher = Files.readString(root.resolve("scripts/demo-remote.ps1"));
        String seedModule = Files.readString(root.resolve("scripts/remote-demo/seed.ps1"));

        assertThat(launcher)
                .contains(
                        "\"RepairPricing\"",
                        "$pricingCoveragePath",
                        "Repair-DemoPricingCoverage"
                );
        assertThat(seedModule)
                .contains(
                        "function Repair-DemoPricingCoverage",
                        "Invoke-DemoPricingCoverageRepair",
                        "914 filas sintéticas"
                );
    }

    @Test
    void reparacionPreservaIdsCantidadYCoberturaAnual() throws IOException {
        String repair = Files.readString(root.resolve("scripts/remote-demo/repair-demo-pricing.sql"));
        String validation = Files.readString(root.resolve("scripts/remote-demo/validate-demo-seed.sql"));

        assertThat(repair)
                .contains(
                        "UPDATE public.disciplina_tarifas t",
                        "WHERE t.id = e.id",
                        "HAVING count(t.id) <> 2",
                        "min(t.vigente_desde) > c.year_start",
                        "count(t.id)"
                )
                .doesNotContain(
                        "DELETE FROM public.disciplina_tarifas",
                        "INSERT INTO public.disciplina_tarifas"
                );

        assertThat(validation)
                .contains(
                        "demo_anchor AS",
                        "substring(",
                        "Actualización de referencia:",
                        "extract(year FROM anchor_date)",
                        "invalid_pricing_coverage",
                        "HAVING count(t.id) <> 2",
                        "min(t.vigente_desde) > b.year_start",
                        "count(*) FROM demo_anchor WHERE anchor_date IS NOT NULL",
                        "= 914"
                )
                .doesNotContain(
                        "extract(month FROM (CURRENT_TIMESTAMP",
                        "extract(day FROM (CURRENT_TIMESTAMP"
                );
    }
}
