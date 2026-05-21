package com.aidrun.backend.user;

import com.aidrun.backend.common.error.ApiException;
import com.aidrun.backend.common.error.ErrorCode;
import com.aidrun.backend.order.RunOrderRepository;
import com.aidrun.backend.order.RunOrderStatus;
import com.aidrun.backend.profile.BlindRunnerProfile;
import com.aidrun.backend.profile.BlindRunnerProfileRepository;
import com.aidrun.backend.profile.VolunteerProfile;
import com.aidrun.backend.profile.VolunteerProfileRepository;
import com.aidrun.backend.profile.dto.BlindRunnerProfileDto;
import com.aidrun.backend.profile.dto.VolunteerProfileDto;
import com.aidrun.backend.user.dto.UserDto;
import com.aidrun.backend.user.dto.UserMeResponse;
import java.util.List;
import java.util.Optional;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class UserService {

    private static final List<RunOrderStatus> ACTIVE_ORDER_STATUSES = List.of(
        RunOrderStatus.ACCEPTED,
        RunOrderStatus.ARRIVED,
        RunOrderStatus.IN_PROGRESS,
        RunOrderStatus.EMERGENCY
    );

    private final AppUserRepository appUserRepository;
    private final RunOrderRepository runOrderRepository;
    private final BlindRunnerProfileRepository blindRunnerProfileRepository;
    private final VolunteerProfileRepository volunteerProfileRepository;

    public UserService(AppUserRepository appUserRepository,
                       RunOrderRepository runOrderRepository,
                       BlindRunnerProfileRepository blindRunnerProfileRepository,
                       VolunteerProfileRepository volunteerProfileRepository) {
        this.appUserRepository = appUserRepository;
        this.runOrderRepository = runOrderRepository;
        this.blindRunnerProfileRepository = blindRunnerProfileRepository;
        this.volunteerProfileRepository = volunteerProfileRepository;
    }

    @Transactional(readOnly = true)
    public UserMeResponse getCurrentUser(String userId) {
        AppUser user = appUserRepository.findById(userId)
            .orElseThrow(() -> new ApiException(ErrorCode.UNAUTHORIZED, "用户不存在", HttpStatus.UNAUTHORIZED));

        Optional<BlindRunnerProfile> brProfile = blindRunnerProfileRepository.findByUser(user);
        Optional<VolunteerProfile> vProfile = volunteerProfileRepository.findByUser(user);

        return new UserMeResponse(
            UserDto.from(user),
            brProfile.map(BlindRunnerProfileDto::from).orElse(null),
            vProfile.map(VolunteerProfileDto::from).orElse(null)
        );
    }

    @Transactional
    public UserDto switchActiveRole(String userId, UserRole newRole) {
        AppUser user = appUserRepository.findById(userId)
            .orElseThrow(() -> new ApiException(ErrorCode.UNAUTHORIZED, "用户不存在", HttpStatus.UNAUTHORIZED));

        if (!user.getRoles().contains(newRole)) {
            throw new ApiException(ErrorCode.UNAUTHORIZED, "用户没有该角色权限", HttpStatus.BAD_REQUEST);
        }

        boolean hasActiveOrder = runOrderRepository.existsByUserIdAndStatusIn(userId, ACTIVE_ORDER_STATUSES);
        if (hasActiveOrder) {
            throw new ApiException(
                ErrorCode.ACTIVE_ORDER_ROLE_SWITCH_BLOCKED,
                "当前存在进行中的订单，暂时不能切换身份",
                HttpStatus.CONFLICT
            );
        }

        user.setActiveRole(newRole);
        appUserRepository.save(user);

        return UserDto.from(user);
    }
}
