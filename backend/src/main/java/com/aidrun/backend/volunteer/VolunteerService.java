package com.aidrun.backend.volunteer;

import com.aidrun.backend.common.error.ApiException;
import com.aidrun.backend.common.error.ErrorCode;
import com.aidrun.backend.profile.AdminReviewStatus;
import com.aidrun.backend.profile.VerificationStatus;
import com.aidrun.backend.profile.VolunteerProfile;
import com.aidrun.backend.profile.VolunteerProfileRepository;
import com.aidrun.backend.profile.dto.VolunteerProfileDto;
import com.aidrun.backend.user.AppUser;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class VolunteerService {

    private final VolunteerProfileRepository volunteerProfileRepository;

    public VolunteerService(VolunteerProfileRepository volunteerProfileRepository) {
        this.volunteerProfileRepository = volunteerProfileRepository;
    }

    public VolunteerProfileDto getVolunteerProfile(AppUser user) {
        VolunteerProfile profile = volunteerProfileRepository.findByUser(user)
            .orElseThrow(() -> new ApiException(
                ErrorCode.PROFILE_INCOMPLETE,
                "请先完善志愿者资料",
                HttpStatus.BAD_REQUEST
            ));
        return VolunteerProfileDto.from(profile);
    }

    @Transactional
    public VolunteerProfileDto mockVerificationApprove(AppUser user) {
        VolunteerProfile profile = volunteerProfileRepository.findByUser(user)
            .orElseThrow(() -> new ApiException(
                ErrorCode.PROFILE_INCOMPLETE,
                "请先完善志愿者资料",
                HttpStatus.BAD_REQUEST
            ));

        profile.setVerificationStatus(VerificationStatus.APPROVED);
        profile.setAdminReviewStatus(AdminReviewStatus.APPROVED);

        VolunteerProfile saved = volunteerProfileRepository.save(profile);
        return VolunteerProfileDto.from(saved);
    }

    /**
     * Update volunteer profile via PUT /api/volunteer/profile.
     * Supports partial updates: nickname and/or isAvailable.
     * Toggling isAvailable requires approved verification status.
     */
    @Transactional
    public VolunteerProfileDto updateVolunteerProfile(AppUser user, String nickname, Boolean isAvailable) {
        VolunteerProfile profile = volunteerProfileRepository.findByUser(user)
            .orElseThrow(() -> new ApiException(
                ErrorCode.PROFILE_INCOMPLETE,
                "请先完善志愿者资料",
                HttpStatus.BAD_REQUEST
            ));

        if (nickname != null && !nickname.isBlank()) {
            profile.setNickname(nickname);
        }

        if (isAvailable != null) {
            if (profile.getVerificationStatus() != VerificationStatus.APPROVED
                || profile.getAdminReviewStatus() != AdminReviewStatus.APPROVED) {
                throw new ApiException(
                    ErrorCode.VOLUNTEER_NOT_APPROVED,
                    "志愿者认证未通过",
                    HttpStatus.FORBIDDEN
                );
            }
            profile.setAvailable(isAvailable);
        }

        VolunteerProfile saved = volunteerProfileRepository.save(profile);
        return VolunteerProfileDto.from(saved);
    }

    public void validateVolunteerCanAcceptOrder(AppUser user) {
        VolunteerProfile profile = volunteerProfileRepository.findByUser(user)
            .orElseThrow(() -> new ApiException(
                ErrorCode.PROFILE_INCOMPLETE,
                "请先完善志愿者资料",
                HttpStatus.BAD_REQUEST
            ));

        if (profile.getVerificationStatus() != VerificationStatus.APPROVED
            || profile.getAdminReviewStatus() != AdminReviewStatus.APPROVED) {
            throw new ApiException(
                ErrorCode.VOLUNTEER_NOT_APPROVED,
                "志愿者认证未通过，不能接单",
                HttpStatus.FORBIDDEN
            );
        }

        if (!profile.isAvailable()) {
            throw new ApiException(
                ErrorCode.VOLUNTEER_NOT_AVAILABLE,
                "请先开启可服务状态",
                HttpStatus.FORBIDDEN
            );
        }
    }
}
