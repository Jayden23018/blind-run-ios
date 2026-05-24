package com.aidrun.backend.user.dto;

import com.aidrun.backend.user.UserRole;
import jakarta.validation.constraints.NotNull;

public record SwitchRoleRequest(
    @NotNull UserRole activeRole
) {
}
