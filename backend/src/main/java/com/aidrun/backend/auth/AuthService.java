package com.aidrun.backend.auth;

import com.aidrun.backend.auth.dto.AuthResponse;
import com.aidrun.backend.common.error.ApiException;
import com.aidrun.backend.common.error.ErrorCode;
import com.aidrun.backend.user.AppUser;
import com.aidrun.backend.user.AppUserRepository;
import com.aidrun.backend.user.UserRole;
import com.aidrun.backend.user.dto.UserDto;
import java.util.LinkedHashSet;
import java.util.Set;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthService {

    private static final String DEMO_VERIFICATION_CODE = "123456";

    private final AppUserRepository appUserRepository;
    private final JwtService jwtService;

    public AuthService(AppUserRepository appUserRepository, JwtService jwtService) {
        this.appUserRepository = appUserRepository;
        this.jwtService = jwtService;
    }

    @Transactional
    public AuthResponse phoneLogin(String phoneNumber, String verificationCode) {
        if (!DEMO_VERIFICATION_CODE.equals(verificationCode)) {
            throw new ApiException(ErrorCode.INVALID_VERIFICATION_CODE, "验证码错误", HttpStatus.BAD_REQUEST);
        }

        AppUser user = appUserRepository.findByPhoneNumber(phoneNumber)
            .orElseGet(() -> {
                Set<UserRole> roles = new LinkedHashSet<>();
                roles.add(UserRole.BLIND_RUNNER);
                roles.add(UserRole.VOLUNTEER);
                AppUser newUser = new AppUser(phoneNumber, roles, null);
                return appUserRepository.save(newUser);
            });

        String accessToken = jwtService.issueAccessToken(user.getId());

        return new AuthResponse(accessToken, "Bearer", UserDto.from(user));
    }
}
