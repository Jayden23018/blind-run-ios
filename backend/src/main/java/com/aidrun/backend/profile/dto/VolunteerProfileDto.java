package com.aidrun.backend.profile.dto;

import com.aidrun.backend.profile.AdminReviewStatus;
import com.aidrun.backend.profile.VerificationStatus;
import com.aidrun.backend.profile.VolunteerProfile;
import java.time.Instant;

public record VolunteerProfileDto(
    String id,
    String userId,
    String nickname,
    String phoneNumber,
    VerificationStatus verificationStatus,
    AdminReviewStatus adminReviewStatus,
    boolean isAvailable,
    int pointsBalance,
    Instant createdAt,
    Instant updatedAt
) {

    public static VolunteerProfileDto from(VolunteerProfile profile) {
        if (profile == null) {
            return null;
        }
        return new VolunteerProfileDto(
            profile.getId(),
            profile.getUser().getId(),
            profile.getNickname(),
            profile.getPhoneNumber(),
            profile.getVerificationStatus(),
            profile.getAdminReviewStatus(),
            profile.isAvailable(),
            profile.getPointsBalance(),
            profile.getCreatedAt(),
            profile.getUpdatedAt()
        );
    }
}
