package gestudio.tenancy;

import com.zaxxer.hikari.HikariDataSource;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.jdbc.DataSourceProperties;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.PlatformTransactionManager;

import javax.sql.DataSource;

@Configuration(proxyBeanMethods = false)
public class PlatformDataSourceConfiguration {

    @Bean
    @ConfigurationProperties("app.platform-datasource")
    DataSourceProperties platformDataSourceProperties() {
        return new DataSourceProperties();
    }

    @Bean(name = "platformDataSource")
    DataSource platformDataSource(
            @Qualifier("platformDataSourceProperties") DataSourceProperties properties) {
        HikariDataSource delegate = properties.initializeDataSourceBuilder()
                .type(HikariDataSource.class)
                .build();
        delegate.setPoolName("GestudioPlatformPool");
        return new TenantAwareDataSource(delegate);
    }

    @Bean(name = "platformJdbcTemplate")
    JdbcTemplate platformJdbcTemplate(@Qualifier("platformDataSource") DataSource dataSource) {
        return new JdbcTemplate(dataSource);
    }

    @Bean(name = "platformTransactionManager")
    PlatformTransactionManager platformTransactionManager(
            @Qualifier("platformDataSource") DataSource dataSource) {
        return new DataSourceTransactionManager(dataSource);
    }
}
