package com.aidrun.backend.volunteer;

import com.aidrun.backend.profile.dto.VolunteerProfileDto;
import com.aidrun.backend.user.AppUser;
import com.aidrun.backend.volunteer.dto.AvailabilityRequest;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/volunteer")
public class VolunteerController {

    private final VolunteerService volunteerService;

    public VolunteerController(VolunteerService volunteerService) {
        this.volunteerService = volunteerService;
    }

    @PostMapping("/mock-verification/approve")
    public ResponseEntity<VolunteerProfileDto> mockVerificationApprove(Authentication authentication) {
        AppUser user = (AppUser) authentication.getPrincipal();
        VolunteerProfileDto result = volunteerService.mockVerificationApprove(user);
        return ResponseEntity.ok(result);
    }

    @PatchMapping("/availability")
    public ResponseEntity<VolunteerProfileDto> updateAvailability(
            @Valid @RequestBody AvailabilityRequest request,
            Authentication authentication) {
        AppUser user = (AppUser) authentication.getPrincipal();
        VolunteerProfileDto result = volunteerService.updateAvailability(user, request.isAvailable());
        return ResponseEntity.ok(result);
    }
}
