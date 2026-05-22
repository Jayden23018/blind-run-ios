package com.aidrun.backend.profile.dto;

import jakarta.validation.constraints.NotBlank;

public record UpdateVolunteerProfileRequest(
    @NotBlank String nickname
) {
}
