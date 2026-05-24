package com.aidrun.backend.volunteer.dto;

import jakarta.validation.constraints.NotNull;

public record AvailabilityRequest(
    @NotNull Boolean isAvailable
) {
}
