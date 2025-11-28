package dk.regionh.integration.amq2ibmmq;

import org.apache.camel.CamelContext;
import org.apache.camel.ProducerTemplate;
import org.apache.camel.builder.RouteBuilder;
import org.apache.camel.component.activemq.ActiveMQComponent;
import org.apache.camel.impl.DefaultCamelContext;

public class MessageSender {

    // implementation 'org.apache.camel:camel-activemq'

    final static String MESSAGE = """
            MSH|^~\\&|Epic||Other||20180405110856|34382|ADT^A31^ADT_A05|52318631|T|2.5
            EVN|A31|20180405110856||REG_UPDATE|34382^WETHJE-STAUN^PERNILLE^^^^^^REGH^^^^^AHH 16
            PID|1||0803781YK2^^^ECPR^ECPR||Ahmed^Marilina||19780308|F|||Nordvangs Alle 1^^ukendt^99^2600^Ukendt^P^^161^Glostrup|999|38665000^PRN^PH^^^^00000000|||||||||||||||||N
            ZPD|||||||N||N
            PD1|||AHH 16, GYNÆKOLOGISK OBSTETRISK AFDELING^^100067
            NK1|1|Volapyk^Ukendt|Andet|Volapyk|^^PH^^^^00000000
            PV1|1
            PV2||||||||||||||||||||||N
            ZPV|||||||||||||||||||||||||||||||0|O
            AL1|1|Lægemid.klas|^ALLERGIES NOT ON FILE
            ZDK
            """;

    public static void main(String[] args) throws Exception {
        // Create Camel context
        CamelContext context = new DefaultCamelContext();
        // Configure the ActiveMQ component with the broker URL.
        // Change the URL if your broker is running on a different host/port.
        ActiveMQComponent activeMQComponent = ActiveMQComponent.activeMQComponent();
        activeMQComponent.setBrokerURL("tcp://tlnxintreg07.unix.regionh.top.local:61616");
        activeMQComponent.setUsername("admin");
        activeMQComponent.setPassword("StrongPass!");
        context.addComponent("activemq", activeMQComponent);
        // Add a route that sends message data from a direct endpoint to a JMS queue.
        context.addRoutes(new RouteBuilder() {
            @Override
            public void configure() throws Exception {
                from("direct:start")
                        .to("activemq:queue:TQUSALLAN_FROM");
            }
        });
        // Start Camel context
        context.start();
        // Create a ProducerTemplate to send messages into the route.
        ProducerTemplate template = context.createProducerTemplate();
        // Send a test message
        template.sendBody("direct:start", MESSAGE);
        System.out.println("Sending");
        // Allow some time for the message to be sent before stopping.
        Thread.sleep(2000);
        // Stop Camel context
        context.stop();
    }
}
