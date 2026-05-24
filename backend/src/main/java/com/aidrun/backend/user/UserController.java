package com.aidrun.backend.user;

import com.aidrun.backend.user.dto.SwitchRoleRequest;
import com.aidrun.backend.user.dto.UserDto;
import com.aidrun.backend.user.dto.UserMeResponse;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/users")
public class UserController {

    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    @GetMapping("/me")
    public ResponseEntity<UserMeResponse> getMe(Authentication authentication) {
        String userId = extractUserId(authentication);
        UserMeResponse response = userService.getCurrentUser(userId);
        return ResponseEntity.ok(response);
    }

    @PatchMapping("/me/active-role")
    public ResponseEntity<UserDto> switchActiveRole(@Valid @RequestBody SwitchRoleRequest request,
                                                    Authentication authentication) {
        String userId = extractUserId(authentication);
        UserDto response = userService.switchActiveRole(userId, request.activeRole());
        return ResponseEntity.ok(response);
    }

    private String extractUserId(Authentication authentication) {
        AppUser user = (AppUser) authentication.getPrincipal();
        return user.getId();
    }
}
