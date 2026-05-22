package com.aidrun.backend.order.dto;

import com.aidrun.backend.order.Cancellation;
import com.aidrun.backend.order.CancelledBy;
import com.aidrun.backend.order.CancellationReason;
import java.time.Instant;

public record CancellationDto(
    String id,
    String orderId,
    CancelledBy cancelledBy,
    CancellationReason cancelledReason,
    String otherReasonText,
    Instant createdAt
) {
    public static CancellationDto from(Cancellation entity) {
        if (entity == null) return null;
        return new CancellationDto(
            entity.getId(),
            entity.getOrder().getId(),
            entity.getCancelledBy(),
            entity.getCancelledReason(),
            entity.getOtherReasonText(),
            entity.getCreatedAt()
        );
    }
}
