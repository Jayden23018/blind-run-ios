package com.aidrun.backend.profile;

import com.aidrun.backend.user.AppUser;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface VolunteerProfileRepository extends JpaRepository<VolunteerProfile, String> {

    Optional<VolunteerProfile> findByUser(AppUser user);
}
