package gestudio.servicios.pdfs;

import com.lowagie.text.pdf.PdfReader;
import com.lowagie.text.pdf.parser.PdfTextExtractor;
import gestudio.entidades.Alumno;
import gestudio.entidades.AplicacionPago;
import gestudio.entidades.Cargo;
import gestudio.entidades.MetodoPago;
import gestudio.entidades.Pago;
import gestudio.repositorios.AplicacionPagoRepositorio;
import gestudio.repositorios.DisciplinaRepositorio;
import gestudio.servicios.disciplina.DisciplinaServicio;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PdfServiceTest {
    @Test
    void reciboRealContienePagoAlumnoFechaCargosEImportesCanonicos() throws Exception {
        var aplicaciones = mock(AplicacionPagoRepositorio.class);
        var service = new PdfService(aplicaciones, mock(DisciplinaServicio.class), mock(DisciplinaRepositorio.class));
        var alumno = new Alumno();
        alumno.setNombre("Marcador");
        alumno.setApellido("Alpha E2E sintetico");
        var metodo = new MetodoPago();
        metodo.setDescripcion("Efectivo sintetico");
        var pago = new Pago();
        pago.setId(987L);
        pago.setAlumno(alumno);
        pago.setMetodoPago(metodo);
        pago.setFecha(LocalDate.of(2026, 10, 23));
        pago.setMontoRecibido(new BigDecimal("120.50"));
        when(aplicaciones.findByPagoIdOrderById(987L)).thenReturn(List.of(
                aplicacion(1001L, "Cuota sintetica", "100.50"),
                aplicacion(1002L, "Matricula sintetica", "20.00")));

        byte[] bytes = service.generarReciboPdf(pago);
        assertThat(bytes).startsWith((byte) '%', (byte) 'P', (byte) 'D', (byte) 'F', (byte) '-');
        var reader = new PdfReader(bytes);
        try {
            assertThat(reader.getNumberOfPages()).isEqualTo(1);
            String text = new PdfTextExtractor(reader).getTextFromPage(1).replaceAll("\\s+", " ");
            assertThat(text).contains("RECIBO N° 987", "Fecha: 2026-10-23",
                    "Alumno: Alpha E2E sintetico Marcador", "Efectivo sintetico",
                    "1001", "Cuota sintetica", "$ 100.50",
                    "1002", "Matricula sintetica", "$ 20.00", "TOTAL RECIBIDO: $ 120.50");
        } finally {
            reader.close();
        }
    }

    private AplicacionPago aplicacion(long cargoId, String concepto, String importe) {
        var cargo = new Cargo();
        cargo.setId(cargoId);
        cargo.setDescripcion(concepto);
        var aplicacion = new AplicacionPago();
        aplicacion.setCargo(cargo);
        aplicacion.setImporteAplicado(new BigDecimal(importe));
        return aplicacion;
    }
}
