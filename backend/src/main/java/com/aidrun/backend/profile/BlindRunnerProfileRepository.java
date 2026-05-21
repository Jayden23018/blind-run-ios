package com.aidrun.backend.profile;

import com.aidrun.backend.user.AppUser;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface BlindRunnerProfileRepository extends JpaRepository<BlindRunnerProfile, String> {

    Optional<BlindRunnerProfile> findByUser(AppUser user);
}
