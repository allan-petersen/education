package dk.regionh.integration.amq2ibmmq;

import ca.uhn.hl7v2.model.Message;
import ca.uhn.hl7v2.parser.PipeParser;
import org.apache.camel.CamelContext;
import org.apache.camel.ProducerTemplate;
import org.apache.camel.builder.RouteBuilder;
import org.apache.camel.component.activemq.ActiveMQComponent;
import org.apache.camel.impl.DefaultCamelContext;

import java.util.HashMap;
import java.util.Map;

public class MessageSender {

    // implementation 'org.apache.camel:camel-activemq'

    final static String MESSAGE =
            "MSH|^~\\&|Epic||Other||20180405110856|34382|ADT^A31^ADT_A05|52318631|T|2.5\r" +
                "EVN|A31|20180405110856||REG_UPDATE|34382^WETHJE-STAUN^PERNILLE^^^^^^REGH^^^^^AHH 16\r" +
                    "PID|1||0803781YK2^^^ECPR^ECPR||Ahmed^Marilina||19780308|F|||Nordvangs Alle 1^^ukendt^99^2600^Ukendt^P^^161^Glostrup|999|38665000^PRN^PH^^^^00000000|||||||||||||||||N\r" +
                    "ZPD|||||||N||N\r" +
                    "PD1|||AHH 16, GYNÆKOLOGISK OBSTETRISK AFDELING^^100067\r" +
                    "NK1|1|Volapyk^Ukendt|Andet|Volapyk|^^PH^^^^00000000\r" +
                    "PV1|1\r" +
                    "PV2||||||||||||||||||||||N\r" +
                    "ZPV|||||||||||||||||||||||||||||||0|O\r" +
                    "AL1|1|Lægemid.klas|^ALLERGIES NOT ON FILE\r" +
                    "ZDK";

    public static void main(String[] args) throws Exception {
        // Create Camel context
        CamelContext context = new DefaultCamelContext();
        // Configure the ActiveMQ component with the broker URL.
        // Change the URL if your broker is running on a different host/port.
        ActiveMQComponent activeMQComponent = ActiveMQComponent.activeMQComponent();
        // activeMQComponent.setBrokerURL("tcp://tlnxintreg07.unix.regionh.top.local:61616");
        // activeMQComponent.setUsername("admin");
        // activeMQComponent.setPassword("StrongPass!");
        activeMQComponent.setBrokerURL("tcp://spt2int01.sp.local:60616");
        activeMQComponent.setUsername("admin");
        activeMQComponent.setPassword("admin");

        context.addComponent("activemq", activeMQComponent);
        // Add a route that sends message data from a direct endpoint to a JMS queue.
        context.addRoutes(new RouteBuilder() {
            @Override
            public void configure() throws Exception {
                from("direct:start")
                        .to("activemq:queue:TQUS200ADTRECEIVER_VISIT.S211AMQ2IBMMQ");
            }
        });
        // Start Camel context
        context.start();
        // Create a ProducerTemplate to send messages into the route.
        ProducerTemplate template = context.createProducerTemplate();
        // Send a test message
        final PipeParser parser = new PipeParser();
        final Message hl7Message = parser.parse(MESSAGE);
        final Map<String, Object> headers = new HashMap<>();
        headers.put("PatientLevelAdtEvent", true);
        headers.put("regionId", "084");
        headers.put("triggerEvent", "A31");
        template.sendBodyAndHeaders("direct:start", hl7Message.encode(), headers);
        System.out.println("Sending");
        // Allow some time for the message to be sent before stopping.
        Thread.sleep(2000);
        // Stop Camel context
        context.stop();
    }
}
