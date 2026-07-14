package gestudio.servicios.pdfs;

import com.lowagie.text.Document;
import com.lowagie.text.DocumentException;
import com.lowagie.text.Element;
import com.lowagie.text.Font;
import com.lowagie.text.PageSize;
import com.lowagie.text.Paragraph;
import com.lowagie.text.Phrase;
import com.lowagie.text.pdf.PdfPCell;
import com.lowagie.text.pdf.PdfPTable;
import com.lowagie.text.pdf.PdfWriter;
import gestudio.dto.reporte.response.ReporteMensualidadResponse;
import gestudio.entidades.AplicacionPago;
import gestudio.entidades.Pago;
import gestudio.repositorios.AplicacionPagoRepositorio;
import gestudio.repositorios.DisciplinaRepositorio;
import gestudio.servicios.disciplina.DisciplinaServicio;
import org.springframework.stereotype.Service;

import java.io.ByteArrayOutputStream;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.Comparator;
import java.util.List;

@Service
public class PdfService {
    private static final Font TITULO = new Font(Font.HELVETICA, 14, Font.BOLD);
    private static final Font ENCABEZADO = new Font(Font.HELVETICA, 9, Font.BOLD);
    private static final Font TEXTO = new Font(Font.HELVETICA, 9, Font.NORMAL);

    private final AplicacionPagoRepositorio aplicaciones;
    private final DisciplinaServicio disciplinas;
    private final DisciplinaRepositorio disciplinaRepositorio;

    public PdfService(AplicacionPagoRepositorio aplicaciones,
                      DisciplinaServicio disciplinas,
                      DisciplinaRepositorio disciplinaRepositorio) {
        this.aplicaciones = aplicaciones;
        this.disciplinas = disciplinas;
        this.disciplinaRepositorio = disciplinaRepositorio;
    }

    public byte[] generarReciboPdf(Pago pago) {
        List<AplicacionPago> detalle = aplicaciones.findByPagoIdOrderById(pago.getId());
        try (ByteArrayOutputStream salida = new ByteArrayOutputStream();
             Document documento = new Document(PageSize.A4)) {
            PdfWriter.getInstance(documento, salida);
            documento.open();
            Paragraph titulo = new Paragraph("RECIBO N° " + pago.getId(), TITULO);
            titulo.setAlignment(Element.ALIGN_CENTER);
            documento.add(titulo);
            documento.add(new Paragraph("Fecha: " + pago.getFecha(), TEXTO));
            documento.add(new Paragraph("Alumno: " + pago.getAlumno().getApellido() + " " + pago.getAlumno().getNombre(), TEXTO));
            documento.add(new Paragraph("Método: " + pago.getMetodoPago().getDescripcion(), TEXTO));
            documento.add(new Paragraph(" "));

            PdfPTable tabla = new PdfPTable(new float[]{1, 5, 2});
            tabla.setWidthPercentage(100);
            encabezado(tabla, "Cargo");
            encabezado(tabla, "Concepto");
            encabezado(tabla, "Aplicado");
            for (AplicacionPago aplicacion : detalle) {
                celda(tabla, aplicacion.getCargo().getId().toString());
                celda(tabla, aplicacion.getCargo().getDescripcion());
                celda(tabla, "$ " + decimal(aplicacion.getImporteAplicado()));
            }
            documento.add(tabla);
            Paragraph total = new Paragraph("TOTAL RECIBIDO: $ " + decimal(pago.getMontoRecibido()), TITULO);
            total.setAlignment(Element.ALIGN_RIGHT);
            documento.add(total);
            if (pago.getObservaciones() != null && !pago.getObservaciones().isBlank()) {
                documento.add(new Paragraph("Observaciones: " + pago.getObservaciones(), TEXTO));
            }
            documento.close();
            return salida.toByteArray();
        } catch (DocumentException e) {
            throw new IllegalStateException("No fue posible generar el recibo", e);
        } catch (Exception e) {
            throw new IllegalStateException("No fue posible cerrar el recibo", e);
        }
    }

    public byte[] generarAlumnosDisciplinaPdf(Long disciplinaId) {
        var disciplina = disciplinaRepositorio.findById(disciplinaId)
                .orElseThrow(() -> new IllegalArgumentException("Disciplina no encontrada"));
        var alumnos = disciplinas.obtenerAlumnosDeDisciplina(disciplinaId).stream()
                .sorted(Comparator.comparing(a -> (a.apellido() + " " + a.nombre()).toLowerCase()))
                .toList();
        try (ByteArrayOutputStream salida = new ByteArrayOutputStream();
             Document documento = new Document(PageSize.A4)) {
            PdfWriter.getInstance(documento, salida);
            documento.open();
            Paragraph titulo = new Paragraph("Alumnos - " + disciplina.getNombre(), TITULO);
            titulo.setAlignment(Element.ALIGN_CENTER);
            documento.add(titulo);
            PdfPTable tabla = new PdfPTable(new float[]{1, 8});
            tabla.setWidthPercentage(100);
            encabezado(tabla, "#");
            encabezado(tabla, "Apellido y nombre");
            for (int i = 0; i < alumnos.size(); i++) {
                celda(tabla, Integer.toString(i + 1));
                celda(tabla, alumnos.get(i).apellido() + " " + alumnos.get(i).nombre());
            }
            documento.add(tabla);
            documento.close();
            return salida.toByteArray();
        } catch (Exception e) {
            throw new IllegalStateException("No fue posible generar el listado", e);
        }
    }

    public byte[] generarLiquidacionProfesorPdf(List<ReporteMensualidadResponse> filas,
                                                 LocalDate desde,
                                                 LocalDate hasta,
                                                 BigDecimal porcentajeEscuela) {
        BigDecimal bruto = filas.stream().map(f -> new BigDecimal(f.importeCobrado()))
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        BigDecimal retencion = bruto.multiply(porcentajeEscuela)
                .divide(new BigDecimal("100"), 2, RoundingMode.HALF_UP);
        BigDecimal neto = bruto.subtract(retencion);
        try (ByteArrayOutputStream salida = new ByteArrayOutputStream();
             Document documento = new Document(PageSize.A4.rotate())) {
            PdfWriter.getInstance(documento, salida);
            documento.open();
            documento.add(new Paragraph("LIQUIDACIÓN DE PROFESOR", TITULO));
            documento.add(new Paragraph("Período: " + desde + " a " + hasta, TEXTO));
            documento.add(new Paragraph("Porcentaje escuela: " + porcentajeEscuela.toPlainString() + "%", TEXTO));
            PdfPTable tabla = new PdfPTable(new float[]{2, 4, 4, 2, 2});
            tabla.setWidthPercentage(100);
            for (String titulo : List.of("Fecha", "Alumno", "Disciplina", "Original", "Cobrado")) {
                encabezado(tabla, titulo);
            }
            for (ReporteMensualidadResponse fila : filas) {
                celda(tabla, fila.fechaEmision().toString());
                celda(tabla, fila.alumno());
                celda(tabla, fila.disciplina());
                celda(tabla, fila.importeOriginal());
                celda(tabla, fila.importeCobrado());
            }
            documento.add(tabla);
            documento.add(new Paragraph("Total cobrado: $ " + decimal(bruto), TITULO));
            documento.add(new Paragraph("Liquidación neta: $ " + decimal(neto), TITULO));
            documento.close();
            return salida.toByteArray();
        } catch (Exception e) {
            throw new IllegalStateException("No fue posible generar la liquidación", e);
        }
    }

    private static void encabezado(PdfPTable tabla, String texto) {
        PdfPCell celda = new PdfPCell(new Phrase(texto, ENCABEZADO));
        celda.setHorizontalAlignment(Element.ALIGN_CENTER);
        tabla.addCell(celda);
    }

    private static void celda(PdfPTable tabla, String texto) {
        tabla.addCell(new PdfPCell(new Phrase(texto == null ? "" : texto, TEXTO)));
    }

    private static String decimal(BigDecimal importe) {
        return importe.setScale(2, RoundingMode.UNNECESSARY).toPlainString();
    }
}
