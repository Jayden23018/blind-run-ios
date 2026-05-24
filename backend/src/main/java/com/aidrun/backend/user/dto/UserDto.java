package com.aidrun.backend.user.dto;

import com.aidrun.backend.user.AppUser;
import com.aidrun.backend.user.UserRole;
import java.time.Instant;
import java.util.Set;

public record UserDto(
    String id,
    String phoneNumber,
    Set<UserRole> roles,
    UserRole activeRole,
    Instant createdAt,
    Instant updatedAt
) {

    public static UserDto from(AppUser user) {
        return new UserDto(
            user.getId(),
            user.getPhoneNumber(),
            user.getRoles(),
            user.getActiveRole(),
            user.getCreatedAt(),
            user.getUpdatedAt()
        );
    }
}
