package gestudio.infra.configuracion;

import org.junit.jupiter.api.Test;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.filter.CorsFilter;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.nio.file.Path;
import java.time.ZoneId;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

class ConfiguracionCorsTest {

    @Test
    void usaSoloLosOrigenesConfigurados() {
        List<String> origins = List.of("http://localhost:5173", "https://example.test");
        var properties = new AppProperties(
                ZoneId.of("America/Argentina/Buenos_Aires"),
                Path.of("receipts"),
                origins
        );
        var source = (UrlBasedCorsConfigurationSource)
                new ConfiguracionCors(properties).corsConfigurationSource();

        assertEquals(origins,
                source.getCorsConfigurations().get("/**").getAllowedOrigins());
    }

    @Test
    void respondePreflightConElOrigenConfigurado() throws Exception {
        var properties = new AppProperties(
                ZoneId.of("America/Argentina/Buenos_Aires"),
                Path.of("receipts"),
                List.of("https://app.example.test")
        );
        var source = new ConfiguracionCors(properties).corsConfigurationSource();
        MockMvc mockMvc = MockMvcBuilders.standaloneSetup(new Object())
                .addFilters(new CorsFilter(source))
                .build();

        mockMvc.perform(options("/api/alumnos")
                        .header("Origin", "https://app.example.test")
                        .header("Access-Control-Request-Method", "GET"))
                .andExpect(status().isOk())
                .andExpect(header().string("Access-Control-Allow-Origin", "https://app.example.test"));
    }
}
