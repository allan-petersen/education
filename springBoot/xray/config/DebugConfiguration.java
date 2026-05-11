package dk.regionh.integration.ik.common.boot.jms.xray.config;

import dk.regionh.integration.ik.common.boot.jms.xray.XRayFactoryPostProcessor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class DebugConfiguration {

    @Bean
    public static XRayFactoryPostProcessor xRayFactoryPostProcessor() {
        return new XRayFactoryPostProcessor();
    }
}
