package com.aidrun.backend.volunteer.dto;

import jakarta.validation.constraints.NotNull;

/**
 * Request body for PUT /api/volunteer/profile.
 * Both fields are optional to support partial updates
 * (e.g. only toggling isAvailable without changing nickname).
 */
public record AvailabilityRequest(
    String nickname,
    Boolean isAvailable
) {
}
