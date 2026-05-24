package com.aidrun.backend.auth;

import com.aidrun.backend.auth.dto.AuthResponse;
import com.aidrun.backend.auth.dto.PhoneLoginRequest;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/phone-login")
    public ResponseEntity<AuthResponse> phoneLogin(@Valid @RequestBody PhoneLoginRequest request) {
        AuthResponse response = authService.phoneLogin(request.phoneNumber(), request.verificationCode());
        return ResponseEntity.ok(response);
    }
}
