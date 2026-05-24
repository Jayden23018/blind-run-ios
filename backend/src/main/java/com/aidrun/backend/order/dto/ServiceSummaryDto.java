package com.aidrun.backend.order.dto;

import com.aidrun.backend.order.ServiceSummary;
import java.time.Instant;

public record ServiceSummaryDto(
    String id,
    String orderId,
    String volunteerUserId,
    String summaryText,
    Instant createdAt
) {
    public static ServiceSummaryDto from(ServiceSummary entity) {
        if (entity == null) return null;
        return new ServiceSummaryDto(
            entity.getId(),
            entity.getOrder().getId(),
            entity.getVolunteerUser().getId(),
            entity.getSummaryText(),
            entity.getCreatedAt()
        );
    }
}
