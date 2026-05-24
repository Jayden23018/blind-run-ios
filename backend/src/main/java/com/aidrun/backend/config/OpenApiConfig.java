package com.aidrun.backend.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OpenApiConfig {

    @Bean
    OpenAPI aidRunOpenApi() {
        return new OpenAPI()
            .info(new Info()
                .title("AidRun MVP Backend")
                .version("0.1.0")
                .description("Spring Boot backend skeleton. Swagger UI loads the frozen MVP contract from /openapi/aidrun-mvp.yaml."));
    }
}
