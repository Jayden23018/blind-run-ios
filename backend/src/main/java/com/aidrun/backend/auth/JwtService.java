package com.aidrun.backend.auth;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;
import java.util.Optional;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class JwtService {

    private final String issuer;

    public JwtService(@Value("${aidrun.jwt.issuer}") String issuer) {
        this.issuer = issuer;
    }

    public String issueAccessToken(String userId) {
        String payload = issuer + ":" + userId + ":" + Instant.now();
        return Base64.getUrlEncoder().withoutPadding().encodeToString(payload.getBytes(StandardCharsets.UTF_8));
    }

    public Optional<String> parseUserId(String token) {
        try {
            String payload = new String(Base64.getUrlDecoder().decode(token), StandardCharsets.UTF_8);
            String[] parts = payload.split(":", 3);
            if (parts.length == 3 && issuer.equals(parts[0])) {
                return Optional.of(parts[1]);
            }
            return Optional.empty();
        } catch (IllegalArgumentException ex) {
            return Optional.empty();
        }
    }
}
