package dk.regionh.integration.ik.common.boot.jms.xray;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.BeansException;
import org.springframework.beans.factory.annotation.AnnotatedBeanDefinition;
import org.springframework.beans.factory.config.BeanDefinition;
import org.springframework.beans.factory.config.BeanFactoryPostProcessor;
import org.springframework.beans.factory.config.ConfigurableListableBeanFactory;
import org.springframework.core.type.MethodMetadata;

import java.util.*;
import java.util.function.Consumer;

/**
 * Sorterer alle beans fra Spring contexten i nedenstående grupper:
 *
 * ”factory processors” – Alle BeanFactoryPostProcessor klasser
 * ”post processors”– Alle BeanPostProcessor klasser
 * ”infrastructure” – Springs egne beans (som ikke er i ovenstående, starter med org.springframework)
 * ”beans” – Resten af beans i application context
 *
 * Desuden er det for hver bean angivet, om den kommer fra autoconfiguration
 *
 */
public class XRayFactoryPostProcessor implements BeanFactoryPostProcessor {

    private static final Logger LOG = LoggerFactory.getLogger(XRayFactoryPostProcessor.class);

    private Map<String, List<String>> beanMap = new HashMap<>();
    private List<String> autoconfiguredBeans = new ArrayList<>();

    private static final String BEAN_FACTORY_POST_PROCESSOR = "BeanFactoryPostProcessor";
    private static final String BEAN_POST_PROCESSOR = "BeanPostProcessor";
    private static final String SPRING_FRAMEWORK = "org.springframework";
    private static final String OTHER = "Other";

    @Override
    public void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) throws BeansException {
        beanMap.put(BEAN_FACTORY_POST_PROCESSOR, new ArrayList<String>());
        beanMap.put(BEAN_POST_PROCESSOR, new ArrayList<String>());
        beanMap.put(SPRING_FRAMEWORK, new ArrayList<String>());
        beanMap.put(OTHER, new ArrayList<String>());
        Arrays.stream(beanFactory.getBeanDefinitionNames()).forEach(entry -> {
            final String name = entry;
            final BeanDefinition beanDefinition = beanFactory.getBeanDefinition(entry);
            if (beanDefinition instanceof AnnotatedBeanDefinition abd) {
                MethodMetadata factoryMethod = abd.getFactoryMethodMetadata();
                if (factoryMethod != null) {
                    final String declaringClass = factoryMethod.getDeclaringClassName();
                    if (declaringClass.contains("autoconfigure")) {
                        autoconfiguredBeans.add(name);
                    }
                }
            }
            if (name.contains(BEAN_FACTORY_POST_PROCESSOR)) {
                beanMap.get(BEAN_FACTORY_POST_PROCESSOR).add(name);
            } else if (name.contains(BEAN_POST_PROCESSOR)) {
                beanMap.get(BEAN_POST_PROCESSOR).add(name);
            } else if (name.contains(SPRING_FRAMEWORK)) {
                beanMap.get(SPRING_FRAMEWORK).add(name);
            } else {
                beanMap.get(OTHER).add(name);
            }
        });
        Consumer<String> output = e -> {
            if (autoconfiguredBeans.contains(e)) {
                System.out.println(e + ". AUTOCONFIGURED");
            } else {
                System.out.println(e);
            }
        };
        System.out.println("\n1. Factory processors:");
        beanMap.get(BEAN_FACTORY_POST_PROCESSOR).forEach(output);
        System.out.println("\n2. Post processors: ");
        beanMap.get(BEAN_POST_PROCESSOR).forEach(output);
        System.out.println("\n3. Infrastructure");
        beanMap.get(SPRING_FRAMEWORK).forEach(output);
        System.out.println("\n4. Other");
        beanMap.get(OTHER).forEach(output);
    }
}
