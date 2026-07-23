package gestudio.controladores;

import gestudio.dto.concepto.ConceptoMapper;
import gestudio.dto.concepto.response.SubConceptoResponse;
import gestudio.entidades.SubConcepto;
import gestudio.repositorios.ConceptoRepositorio;
import gestudio.servicios.concepto.ConceptoServicio;
import gestudio.servicios.concepto.SubConceptoServicio;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class ConceptoControladorTest {

    private SubConceptoServicio subConceptos;
    private ConceptoRepositorio conceptos;
    private ConceptoControlador controller;

    @BeforeEach
    void setUp() {
        subConceptos = mock(SubConceptoServicio.class);
        conceptos = mock(ConceptoRepositorio.class);
        controller = new ConceptoControlador(
                mock(ConceptoServicio.class),
                subConceptos,
                conceptos,
                mock(ConceptoMapper.class)
        );
    }

    @Test
    void selectorNumericoResuelveElSubconceptoPorId() {
        when(subConceptos.obtenerSubConceptoPorId(1L))
                .thenReturn(new SubConceptoResponse(1L, "INDUMENTARIA"));
        when(conceptos.findBySubConceptoId(1L)).thenReturn(List.of());

        var response = controller.listarConceptosPorSubConcepto("1");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
        verify(conceptos).findBySubConceptoId(1L);
        verify(subConceptos, never()).findByDescripcionIgnoreCase("1");
    }

    @Test
    void selectorTextualConservaLaBusquedaLegacyPorDescripcion() {
        when(subConceptos.findByDescripcionIgnoreCase("INDUMENTARIA"))
                .thenReturn(new SubConcepto(7L, "INDUMENTARIA", true));
        when(conceptos.findBySubConceptoId(7L)).thenReturn(List.of());

        var response = controller.listarConceptosPorSubConcepto("INDUMENTARIA");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
        verify(conceptos).findBySubConceptoId(7L);
    }

    @Test
    void selectorInexistenteDevuelveNotFound() {
        when(subConceptos.obtenerSubConceptoPorId(99L))
                .thenThrow(new IllegalArgumentException("No existe"));
        when(subConceptos.findByDescripcionIgnoreCase("99")).thenReturn(null);

        var response = controller.listarConceptosPorSubConcepto("99");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        verify(conceptos, never()).findBySubConceptoId(99L);
    }
}
