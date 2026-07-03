package ledance.cuotas.application;

import ledance.entidades.Cargo;
import ledance.entidades.Usuario;
import ledance.tarifas.persistence.CondicionEconomicaInscripcion;
import ledance.tarifas.persistence.TarifaDisciplina;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.LocalDate;

@Service
public class LiquidacionCargoServicio {
    private final JdbcTemplate jdbc;

    public LiquidacionCargoServicio(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void registrar(Cargo cargo, LocalDate periodoDesde, TarifaDisciplina tarifa,
                          CondicionEconomicaInscripcion condicion, String origenPrecio,
                          BigDecimal importeBase, BigDecimal descuentoPorcentaje,
                          BigDecimal descuentoImporte, BigDecimal importeFinal,
                          int formulaVersion, String observaciones, Usuario actor) {
        jdbc.update("""
                INSERT INTO cargo_liquidaciones(
                    cargo_id, periodo_desde, tarifa_disciplina_id, condicion_inscripcion_id,
                    origen_precio, importe_base, descuento_porcentaje, descuento_importe,
                    recargo_porcentaje, recargo_importe, importe_final, formula_version,
                    observaciones, calculada_por_usuario_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?, ?, ?)
                """, cargo.getId(), periodoDesde, tarifa == null ? null : tarifa.getId(),
                condicion == null ? null : condicion.getId(), origenPrecio, importeBase,
                descuentoPorcentaje, descuentoImporte, importeFinal, formulaVersion,
                observaciones, actor == null ? null : actor.getId());
    }
}
