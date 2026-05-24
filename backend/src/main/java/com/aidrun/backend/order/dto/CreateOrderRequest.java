package com.aidrun.backend.order.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.time.Instant;

public record CreateOrderRequest(
    @NotNull @Valid LocationPointDto startLocation,
    @NotNull Instant appointmentTime,
    String destinationText,
    Integer estimatedDurationMinutes,
    BigDecimal estimatedDistanceKm,
    String pacePreference,
    Boolean preferSameGender,
    String remark
) {
}
