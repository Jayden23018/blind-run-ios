package com.aidrun.backend.profile;

import com.aidrun.backend.profile.dto.BlindRunnerProfileDto;
import com.aidrun.backend.profile.dto.UpdateBlindRunnerProfileRequest;
import com.aidrun.backend.profile.dto.UpdateVolunteerProfileRequest;
import com.aidrun.backend.profile.dto.VolunteerProfileDto;
import com.aidrun.backend.user.AppUser;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/profiles")
public class ProfileController {

    private final ProfileService profileService;

    public ProfileController(ProfileService profileService) {
        this.profileService = profileService;
    }

    @PutMapping("/blind-runner")
    public ResponseEntity<BlindRunnerProfileDto> upsertBlindRunnerProfile(
            @Valid @RequestBody UpdateBlindRunnerProfileRequest request,
            Authentication authentication) {
        AppUser user = (AppUser) authentication.getPrincipal();
        BlindRunnerProfileDto result = profileService.upsertBlindRunnerProfile(user, request);
        return ResponseEntity.ok(result);
    }

    @PutMapping("/volunteer")
    public ResponseEntity<VolunteerProfileDto> upsertVolunteerProfile(
            @Valid @RequestBody UpdateVolunteerProfileRequest request,
            Authentication authentication) {
        AppUser user = (AppUser) authentication.getPrincipal();
        VolunteerProfileDto result = profileService.upsertVolunteerProfile(user, request);
        return ResponseEntity.ok(result);
    }
}
