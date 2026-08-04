package gestudio.tenancy;

import com.zaxxer.hikari.HikariDataSource;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.jdbc.DataSourceProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;

import javax.sql.DataSource;

@Configuration(proxyBeanMethods = false)
@ConditionalOnProperty(name = "app.multitenancy.required", havingValue = "true", matchIfMissing = true)
public class TenantDataSourceConfiguration {

    @Bean
    @Primary
    DataSource dataSource(DataSourceProperties properties) {
        HikariDataSource delegate = properties.initializeDataSourceBuilder()
                .type(HikariDataSource.class)
                .build();
        return new TenantAwareDataSource(delegate);
    }
}
