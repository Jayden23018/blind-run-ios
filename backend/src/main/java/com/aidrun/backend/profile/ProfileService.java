package com.aidrun.backend.profile;

import com.aidrun.backend.profile.dto.BlindRunnerProfileDto;
import com.aidrun.backend.profile.dto.EmergencyContactRequest;
import com.aidrun.backend.profile.dto.UpdateBlindRunnerProfileRequest;
import com.aidrun.backend.profile.dto.UpdateVolunteerProfileRequest;
import com.aidrun.backend.profile.dto.VolunteerProfileDto;
import com.aidrun.backend.user.AppUser;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ProfileService {

    private final BlindRunnerProfileRepository blindRunnerProfileRepository;
    private final VolunteerProfileRepository volunteerProfileRepository;

    public ProfileService(BlindRunnerProfileRepository blindRunnerProfileRepository,
                          VolunteerProfileRepository volunteerProfileRepository) {
        this.blindRunnerProfileRepository = blindRunnerProfileRepository;
        this.volunteerProfileRepository = volunteerProfileRepository;
    }

    @Transactional
    public BlindRunnerProfileDto upsertBlindRunnerProfile(AppUser user, UpdateBlindRunnerProfileRequest request) {
        BlindRunnerProfile profile = blindRunnerProfileRepository.findByUser(user).orElse(null);

        if (profile == null) {
            profile = new BlindRunnerProfile(user, request.nickname(), request.runningExperience());
            EmergencyContact contact = new EmergencyContact(
                request.emergencyContact().name(),
                request.emergencyContact().phoneNumber()
            );
            profile.setEmergencyContact(contact);
        } else {
            profile.setNickname(request.nickname());
            profile.setRunningExperience(request.runningExperience());
            EmergencyContact contact = profile.getEmergencyContact();
            if (contact != null) {
                contact.setName(request.emergencyContact().name());
                contact.setPhoneNumber(request.emergencyContact().phoneNumber());
            } else {
                EmergencyContact newContact = new EmergencyContact(
                    request.emergencyContact().name(),
                    request.emergencyContact().phoneNumber()
                );
                profile.setEmergencyContact(newContact);
            }
        }

        BlindRunnerProfile saved = blindRunnerProfileRepository.save(profile);
        return BlindRunnerProfileDto.from(saved);
    }

    @Transactional
    public VolunteerProfileDto upsertVolunteerProfile(AppUser user, UpdateVolunteerProfileRequest request) {
        VolunteerProfile profile = volunteerProfileRepository.findByUser(user).orElse(null);

        if (profile == null) {
            profile = new VolunteerProfile(
                user,
                request.nickname(),
                user.getPhoneNumber(),
                VerificationStatus.NOT_SUBMITTED,
                AdminReviewStatus.NOT_SUBMITTED,
                false,
                0
            );
        } else {
            profile.setNickname(request.nickname());
        }

        VolunteerProfile saved = volunteerProfileRepository.save(profile);
        return VolunteerProfileDto.from(saved);
    }
}
