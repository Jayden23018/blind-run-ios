package com.aidrun.backend.auth.dto;

import com.aidrun.backend.user.dto.UserDto;

public record AuthResponse(
    String accessToken,
    String tokenType,
    UserDto user
) {
}
