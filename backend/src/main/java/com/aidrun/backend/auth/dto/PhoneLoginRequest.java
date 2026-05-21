package com.aidrun.backend.auth.dto;

import jakarta.validation.constraints.NotBlank;

public record PhoneLoginRequest(
    @NotBlank String phoneNumber,
    @NotBlank String verificationCode
) {
}
