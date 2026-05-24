package com.aidrun.backend.profile.dto;

import com.aidrun.backend.profile.BlindRunnerProfile;
import java.time.Instant;

public record BlindRunnerProfileDto(
    String id,
    String userId,
    String nickname,
    String runningExperience,
    EmergencyContactDto emergencyContact,
    Instant createdAt,
    Instant updatedAt
) {

    public static BlindRunnerProfileDto from(BlindRunnerProfile profile) {
        if (profile == null) {
            return null;
        }
        return new BlindRunnerProfileDto(
            profile.getId(),
            profile.getUser().getId(),
            profile.getNickname(),
            profile.getRunningExperience(),
            EmergencyContactDto.from(profile.getEmergencyContact()),
            profile.getCreatedAt(),
            profile.getUpdatedAt()
        );
    }
}
