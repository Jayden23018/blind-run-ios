package com.aidrun.backend.profile.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public record UpdateBlindRunnerProfileRequest(
    @NotBlank String nickname,
    String runningExperience,
    @NotNull @Valid EmergencyContactRequest emergencyContact
) {
}
