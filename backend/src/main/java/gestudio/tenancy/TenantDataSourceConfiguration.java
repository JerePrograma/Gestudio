package gestudio.tenancy;

import com.zaxxer.hikari.HikariDataSource;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.jdbc.DataSourceProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;

import javax.sql.DataSource;

@Configuration(proxyBeanMethods = false)
@ConditionalOnProperty(name = "app.multitenancy.required", havingValue = "true", matchIfMissing = true)
public class TenantDataSourceConfiguration {

    @Bean
    @Primary
    DataSource dataSource(
            @Qualifier("spring.datasource-org.springframework.boot.autoconfigure.jdbc.DataSourceProperties")
            DataSourceProperties properties) {
        HikariDataSource delegate = properties.initializeDataSourceBuilder()
                .type(HikariDataSource.class)
                .build();
        return new TenantAwareDataSource(delegate);
    }

    @Bean
    @Primary
    JdbcTemplate jdbcTemplate(@Qualifier("dataSource") DataSource dataSource) {
        return new JdbcTemplate(dataSource);
    }
}
