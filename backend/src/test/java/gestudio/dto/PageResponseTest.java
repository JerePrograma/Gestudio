package gestudio.dto;

import org.junit.jupiter.api.Test;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PageResponseTest {

    @Test
    void convierteUnaPaginaEnElContratoEstable() {
        var page = new PageImpl<>(List.of("tres", "cuatro"), PageRequest.of(1, 2), 5);

        PageResponse<String> response = PageResponse.from(page);

        assertEquals(List.of("tres", "cuatro"), response.content());
        assertEquals(5, response.totalElements());
        assertEquals(3, response.totalPages());
        assertEquals(2, response.size());
        assertEquals(1, response.number());
        assertFalse(response.first());
        assertFalse(response.last());
    }

    @Test
    void representaUnaPaginaVaciaSinDivisionPorCero() {
        PageResponse<String> response = PageResponse.from(new PageImpl<>(List.of()));

        assertTrue(response.content().isEmpty());
        assertEquals(0, response.totalElements());
        assertEquals(0, response.totalPages());
        assertEquals(0, response.size());
        assertEquals(0, response.number());
        assertTrue(response.first());
        assertTrue(response.last());
    }
}
