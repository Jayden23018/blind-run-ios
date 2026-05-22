package com.aidrun.backend.profile.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

public record EmergencyContactRequest(
    @NotBlank String name,
    @NotBlank @Pattern(regexp = "^1\\d{10}$") String phoneNumber
) {
}
