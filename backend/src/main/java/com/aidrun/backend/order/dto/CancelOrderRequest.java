package com.aidrun.backend.order.dto;

import com.aidrun.backend.order.CancellationReason;
import jakarta.validation.constraints.NotNull;

public record CancelOrderRequest(
    @NotNull CancellationReason cancelledReason,
    String otherReasonText
) {
}
