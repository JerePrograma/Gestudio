package gestudio.infra.configuracion;

import gestudio.infra.observabilidad.RequestCorrelationFilter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import java.util.List;

@Configuration
public class ConfiguracionCors implements WebMvcConfigurer {

    private final AppProperties properties;

    public ConfiguracionCors(AppProperties properties) {
        this.properties = properties;
    }

    @Bean
    CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuration = new CorsConfiguration();

        configuration.setAllowedOrigins(properties.corsAllowedOrigins());

        configuration.setAllowedMethods(List.of("GET", "POST", "OPTIONS", "PUT", "DELETE", "PATCH"));
        configuration.setAllowedHeaders(List.of(
                "Authorization", "Content-Type", "Accept", RequestCorrelationFilter.HEADER_NAME));
        configuration.setExposedHeaders(List.of("Authorization", RequestCorrelationFilter.HEADER_NAME));
        configuration.setAllowCredentials(true);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", configuration);
        return source;
    }
}
