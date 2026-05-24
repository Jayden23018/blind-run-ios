package com.aidrun.backend.order.dto;

import com.aidrun.backend.order.EmergencyEvent;
import com.aidrun.backend.order.RunOrderStatus;
import com.aidrun.backend.user.UserRole;
import java.time.Instant;

public record EmergencyEventDto(
    String id,
    String orderId,
    UserRole triggeredByRole,
    RunOrderStatus previousStatus,
    String note,
    Instant createdAt
) {
    public static EmergencyEventDto from(EmergencyEvent entity) {
        if (entity == null) return null;
        return new EmergencyEventDto(
            entity.getId(),
            entity.getOrder().getId(),
            entity.getTriggeredByRole(),
            entity.getPreviousStatus(),
            entity.getNote(),
            entity.getCreatedAt()
        );
    }
}
