package com.aidrun.backend.order.dto;

import com.aidrun.backend.order.RunOrder;
import com.aidrun.backend.order.RunOrderStatus;
import java.math.BigDecimal;
import java.time.Instant;

public record RunOrderDto(
    String id,
    String blindRunnerUserId,
    String blindRunnerNickname,
    String blindRunnerPhone,
    String volunteerUserId,
    String volunteerNickname,
    RunOrderStatus status,
    LocationPointDto startLocation,
    String destinationText,
    Instant appointmentTime,
    Integer estimatedDurationMinutes,
    BigDecimal estimatedDistanceKm,
    String pacePreference,
    Boolean preferSameGender,
    String remark,
    CancellationDto cancellation,
    EmergencyEventDto emergencyEvent,
    ServiceSummaryDto serviceSummary,
    RatingDto rating,
    Instant createdAt,
    Instant acceptedAt,
    Instant arrivedAt,
    Instant startedAt,
    Instant completedAt,
    Instant cancelledAt,
    Instant emergencyAt,
    Instant updatedAt
) {
    public static RunOrderDto from(RunOrder order, boolean showBlindRunnerPhone) {
        return new RunOrderDto(
            order.getId(),
            order.getBlindRunnerUser().getId(),
            order.getBlindRunnerNickname(),
            showBlindRunnerPhone ? order.getBlindRunnerPhone() : null,
            order.getVolunteerUser() != null ? order.getVolunteerUser().getId() : null,
            order.getVolunteerNickname(),
            order.getStatus(),
            LocationPointDto.from(order.getStartLocation()),
            order.getDestinationText(),
            order.getAppointmentTime(),
            order.getEstimatedDurationMinutes(),
            order.getEstimatedDistanceKm(),
            order.getPacePreference(),
            order.getPreferSameGender(),
            order.getRemark(),
            CancellationDto.from(order.getCancellation()),
            EmergencyEventDto.from(order.getEmergencyEvent()),
            ServiceSummaryDto.from(order.getServiceSummary()),
            RatingDto.from(order.getRating()),
            order.getCreatedAt(),
            order.getAcceptedAt(),
            order.getArrivedAt(),
            order.getStartedAt(),
            order.getCompletedAt(),
            order.getCancelledAt(),
            order.getEmergencyAt(),
            order.getUpdatedAt()
        );
    }
}
