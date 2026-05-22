package com.aidrun.backend.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

public record PhoneLoginRequest(
    @NotBlank
    @Pattern(regexp = "^1\\d{10}$")
    String phoneNumber,
    @NotBlank String verificationCode
) {
}
