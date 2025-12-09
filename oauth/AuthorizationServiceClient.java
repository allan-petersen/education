package dk.regionh.integration.epic2pro.oauth2.authorizationservice;

import com.auth0.jwt.JWT;
import com.auth0.jwt.JWTVerifier;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.interfaces.DecodedJWT;
import dk.regionh.integration.epic2pro.oauth2.AccessTokenResponse;
import dk.regionh.integration.ik.common.configuration.Config;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestTemplate;

import java.io.FileInputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.KeyFactory;
import java.security.NoSuchAlgorithmException;
import java.security.cert.CertificateException;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.InvalidKeySpecException;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.*;
import java.util.Base64;
import java.util.UUID;

@Component
public class AuthorizationServiceClient {

    // TODO OAuth2 The Oauth stuff should go into a library
    // TODO OAuth2 Put the private key in a p12 file, where the password is in secret-server.settings and in KeyPass
    // TODO OAuth2 Change the code to request a new AccessToken, if the request fail with an access_token expired exception. Test it.
    // TODO OAuth2 Add code to generate JSON Web Key Sets from the public key. (Epic recommends your application provide the kid field in JWK Sets and in your JWT Headers)
    //      This is a separate program to be started form the command line.
    // TODO OAuth2 How do we publish our public key to a central place?
    // TODO OAuth2. This code must validate the access token. See SLG https://sherlock.epic.com/default.aspx?view=slg/home#id=9168671&rv=1 post 21 and post 22

    private static final String KEY_DIR = "./src/main/env/local/fixed/";
    private static final String PRIVATE_KEY = "S401-Epic2PRO-private.pem";
    private static final String PUBLIC_KEY = "S401-Epic2PRO-public.pem";

    public AccessTokenResponse getAccessToken() throws IOException, NoSuchAlgorithmException, InvalidKeySpecException, CertificateException {
        // Load your private key
        String privateKeyContent = new String(Files.readAllBytes(Paths.get(KEY_DIR + PRIVATE_KEY)));
        privateKeyContent = privateKeyContent
                .replace("-----BEGIN PRIVATE KEY-----", "")
                .replace("-----END PRIVATE KEY-----", "")
                .replaceAll("\\s", "");
        final byte[] privateKeyBytes = Base64.getDecoder().decode(privateKeyContent);
        final PKCS8EncodedKeySpec keySpec = new PKCS8EncodedKeySpec(privateKeyBytes);
        final KeyFactory keyFactory = KeyFactory.getInstance("RSA");
        final RSAPrivateKey privateKey = (RSAPrivateKey) keyFactory.generatePrivate(keySpec);

        // Load your public key from the certificate
        final FileInputStream fis = new FileInputStream(KEY_DIR + PUBLIC_KEY);
        final CertificateFactory certFactory = CertificateFactory.getInstance("X.509");
        final X509Certificate certificate = (X509Certificate) certFactory.generateCertificate(fis);
        final RSAPublicKey publicKey = (RSAPublicKey) certificate.getPublicKey();

        // Create the JWT
        // Define the JWT header containing type of token and the signing algorithm
        // The JWT header is implicitly set when you specify the signing algorithm using the  Algorithm.RSA256  method. The  java-jwt  library automatically includes the header information based on the algorithm you choose.
        // Type of Token ( typ )**: This is automatically set to  JWT  by the library when you create a token using the  JWT.create()  method. This is a default behavior for most JWT libraries.
        //  Signing Algorithm ( alg )**: This is specified when you create the  Algorithm  instance. For example, when you use  Algorithm.RSA256(publicKey, privateKey) , the library sets the  alg  header to  RS256 .
        //
        // Sign the JWT. Use your private key to sign the token. The specific method will depend on the library you're using,
        // but it generally involves specifying the header, payload, and private key.
        // In the  Algorithm.RSA256  method, both keys are included to emphasize the dual roles they play:
        // Private Key**: Required for signing the JWT.
        // Public Key**: Required for verifying the JWT.
        // In practice, when creating the token, you only need the private key. When verifying the token, you only need the public key.
        // However, libraries often require both keys to be specified for flexibility and to support both operations in one interface.
        // This design can also simplify scenarios where the same code might be used for both signing and verifying tokens, such as in testing environments.
        final Algorithm algorithm = Algorithm.RSA384(publicKey, privateKey);

        final LocalDateTime now = LocalDateTime.now();

        // Convert it to a ZonedDateTime in UTC
        final ZonedDateTime nowInUtc = now.atZone(ZoneId.systemDefault()).withZoneSameInstant(ZoneId.of("UTC"));

        // Convert to LocalDateTime
        LocalDateTime localDateTimeInUtc = nowInUtc.toLocalDateTime().plusSeconds(60);
        Instant instant = localDateTimeInUtc.toInstant(ZoneOffset.UTC);
        final long authenticationJwtExpireTime = instant.getEpochSecond();

        // Create the JWT Payload. The payload contains the claims.
        final String token = JWT.create()
                .withSubject(Config.getString("epic.client.id"))
                .withClaim("iss", Config.getString("epic.client.id"))
                .withClaim("aud", Config.getString("epic.authorization.server.url"))
                .withClaim("jti", UUID.randomUUID().toString())
                .withClaim("exp", authenticationJwtExpireTime)
                .sign(algorithm);

        System.out.println("Generated Token: " + token);

        // Verify the JWT
        final JWTVerifier verifier = JWT.require(algorithm)
                .build();
        final DecodedJWT jwt = verifier.verify(token);

        System.out.println("Decoded Subject: " + jwt.getSubject());
        System.out.println("Decoded iss: " + jwt.getClaim("iss").asString());
        System.out.println("Decoded aud: " + jwt.getClaim("aud").asString());
        System.out.println("Decoded jti: " + jwt.getClaim("jti").asString());
        System.out.println("Decoded exp: " + jwt.getClaim("exp").asLong());

        final LocalDateTime dateTime = LocalDateTime.ofInstant(
                Instant.ofEpochSecond(authenticationJwtExpireTime),
                ZoneOffset.UTC
        );
        System.out.println("Decoded exp as dateTime: " + dateTime);

        final RestTemplate restTemplate = new RestTemplate();
        final String baseUrl = Config.getString("epic.authorization.server.url");

        final HttpHeaders headers = new HttpHeaders();
        // Content-Type: application/x-www-form-urlencoded
        headers.set("Content-Type", "application/x-www-form-urlencoded");


        // The following form-urlencoded parameters are required in the POST body:
        // grant_type: This should be set to client_credentials.
        // client_assertion_type: This should be set to urn:ietf:params:oauth:client-assertion-type:jwt-bearer
        // client_assertion: This should be set to the JWT you created above.
        final MultiValueMap<String, String> body = new LinkedMultiValueMap<>();
        body.add("grant_type", "client_credentials");
        body.add("client_assertion_type", "urn:ietf:params:oauth:client-assertion-type:jwt-bearer");
        body.add("client_assertion", token);

        final HttpEntity<MultiValueMap<String, String>> entity = new HttpEntity<>(body, headers);

        // POST the JWT to Token Endpoint to Obtain Access Token
        // Make HTTP POST request to the authorization server's OAuth 2.0 token endpoint to obtain access token.
        final ResponseEntity<AccessTokenResponse> response = restTemplate.exchange(baseUrl, HttpMethod.POST, entity, AccessTokenResponse.class);

        // Access token example
        //
        // {
        //    "access_token": "i82fGhXNxmidCt0OdjYttm2x0cOKU1ZbN6Y_-zBvt2kw3xn-MY3gY4lOXPee6iKPw3JncYBT1Y-kdPpBYl-lsmUlA4x5dUVC1qbjEi1OHfe_Oa-VRUAeabnMLjYgKI7b",
        //        "token_type": "bearer",
        //        "expires_in": 3600,
        //        "scope": "Patient.read Patient.search"
        // }
        System.out.println(response);
        return response.getBody();
    }

}
