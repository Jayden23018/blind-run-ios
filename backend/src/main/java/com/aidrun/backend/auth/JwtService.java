package com.aidrun.backend.auth;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;
import java.util.Map;
import java.util.Optional;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class JwtService {

    private static final TypeReference<Map<String, Object>> MAP_TYPE = new TypeReference<>() {
    };
    private static final String HMAC_SHA256 = "HmacSHA256";
    private static final Base64.Encoder BASE64_URL_ENCODER = Base64.getUrlEncoder().withoutPadding();
    private static final Base64.Decoder BASE64_URL_DECODER = Base64.getUrlDecoder();

    private final String issuer;
    private final String secret;
    private final ObjectMapper objectMapper;

    public JwtService(@Value("${aidrun.jwt.issuer}") String issuer,
                      @Value("${aidrun.jwt.demo-secret}") String secret,
                      ObjectMapper objectMapper) {
        this.issuer = issuer;
        this.secret = secret;
        this.objectMapper = objectMapper;
    }

    public String issueAccessToken(String userId) {
        try {
            String header = base64UrlEncode(objectMapper.writeValueAsBytes(Map.of(
                "alg", "HS256",
                "typ", "JWT"
            )));
            String payload = base64UrlEncode(objectMapper.writeValueAsBytes(Map.of(
                "iss", issuer,
                "sub", userId,
                "iat", Instant.now().getEpochSecond()
            )));
            String signingInput = header + "." + payload;
            return signingInput + "." + sign(signingInput);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("Unable to issue access token", ex);
        }
    }

    public Optional<String> parseUserId(String token) {
        String[] parts = token.split("\\.");
        if (parts.length != 3) {
            return Optional.empty();
        }

        String signingInput = parts[0] + "." + parts[1];
        if (!constantTimeEquals(sign(signingInput), parts[2])) {
            return Optional.empty();
        }

        try {
            Map<String, Object> payload = objectMapper.readValue(BASE64_URL_DECODER.decode(parts[1]), MAP_TYPE);
            Object tokenIssuer = payload.get("iss");
            Object subject = payload.get("sub");
            if (issuer.equals(tokenIssuer) && subject instanceof String userId && !userId.isBlank()) {
                return Optional.of(userId);
            }
            return Optional.empty();
        } catch (IllegalArgumentException | IOException ex) {
            return Optional.empty();
        }
    }

    private String base64UrlEncode(byte[] value) {
        return BASE64_URL_ENCODER.encodeToString(value);
    }

    private String sign(String signingInput) {
        try {
            Mac mac = Mac.getInstance(HMAC_SHA256);
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), HMAC_SHA256));
            return base64UrlEncode(mac.doFinal(signingInput.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception ex) {
            throw new IllegalStateException("Unable to sign access token", ex);
        }
    }

    private boolean constantTimeEquals(String expected, String actual) {
        byte[] expectedBytes = expected.getBytes(StandardCharsets.UTF_8);
        byte[] actualBytes = actual.getBytes(StandardCharsets.UTF_8);
        if (expectedBytes.length != actualBytes.length) {
            return false;
        }

        int result = 0;
        for (int i = 0; i < expectedBytes.length; i += 1) {
            result |= expectedBytes[i] ^ actualBytes[i];
        }
        return result == 0;
    }
}
