package gestudio.infra.configuracion;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;

@Configuration
public class TimeConfiguration {

    @Bean
    public Clock applicationClock(AppProperties properties) {
        return Clock.system(properties.timeZone());
    }
}
