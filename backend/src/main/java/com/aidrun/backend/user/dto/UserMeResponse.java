package com.aidrun.backend.user.dto;

import com.aidrun.backend.profile.dto.BlindRunnerProfileDto;
import com.aidrun.backend.profile.dto.VolunteerProfileDto;

public record UserMeResponse(
    UserDto user,
    BlindRunnerProfileDto blindRunnerProfile,
    VolunteerProfileDto volunteerProfile
) {
}
