package com.aidrun.backend.order.dto;

import com.aidrun.backend.order.OrderRating;
import java.time.Instant;

public record RatingDto(
    String id,
    String orderId,
    String blindRunnerUserId,
    String volunteerUserId,
    int stars,
    String comment,
    Instant createdAt
) {
    public static RatingDto from(OrderRating entity) {
        if (entity == null) return null;
        return new RatingDto(
            entity.getId(),
            entity.getOrder().getId(),
            entity.getBlindRunnerUser().getId(),
            entity.getVolunteerUser().getId(),
            entity.getStars(),
            entity.getComment(),
            entity.getCreatedAt()
        );
    }
}
