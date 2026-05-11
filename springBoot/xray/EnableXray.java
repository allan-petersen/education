package dk.regionh.integration.ik.common.boot.jms.xray;

import dk.regionh.integration.ik.common.boot.jms.xray.config.DebugConfiguration;
import org.springframework.context.annotation.Import;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Enable XRay.
 */
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Import(DebugConfiguration.class)
public @interface EnableXray {
}
