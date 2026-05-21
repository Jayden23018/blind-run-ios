package com.aidrun.backend.seed;

import com.aidrun.backend.location.LocationPoint;
import com.aidrun.backend.location.LocationSource;
import com.aidrun.backend.order.RunOrder;
import com.aidrun.backend.order.RunOrderRepository;
import com.aidrun.backend.order.RunOrderStatus;
import com.aidrun.backend.profile.AdminReviewStatus;
import com.aidrun.backend.profile.BlindRunnerProfile;
import com.aidrun.backend.profile.BlindRunnerProfileRepository;
import com.aidrun.backend.profile.EmergencyContact;
import com.aidrun.backend.profile.VerificationStatus;
import com.aidrun.backend.profile.VolunteerProfile;
import com.aidrun.backend.profile.VolunteerProfileRepository;
import com.aidrun.backend.user.AppUser;
import com.aidrun.backend.user.AppUserRepository;
import com.aidrun.backend.user.UserRole;
import com.aidrun.backend.volunteer.VolunteerPointsLedger;
import com.aidrun.backend.volunteer.VolunteerPointsLedgerRepository;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Set;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
public class DemoDataSeeder implements CommandLineRunner {

    private final AppUserRepository userRepository;
    private final BlindRunnerProfileRepository blindRunnerProfileRepository;
    private final VolunteerProfileRepository volunteerProfileRepository;
    private final RunOrderRepository runOrderRepository;
    private final VolunteerPointsLedgerRepository pointsLedgerRepository;

    public DemoDataSeeder(
        AppUserRepository userRepository,
        BlindRunnerProfileRepository blindRunnerProfileRepository,
        VolunteerProfileRepository volunteerProfileRepository,
        RunOrderRepository runOrderRepository,
        VolunteerPointsLedgerRepository pointsLedgerRepository
    ) {
        this.userRepository = userRepository;
        this.blindRunnerProfileRepository = blindRunnerProfileRepository;
        this.volunteerProfileRepository = volunteerProfileRepository;
        this.runOrderRepository = runOrderRepository;
        this.pointsLedgerRepository = pointsLedgerRepository;
    }

    @Override
    @Transactional
    public void run(String... args) {
        if (userRepository.count() > 0) {
            return;
        }

        AppUser blindRunner = userRepository.save(new AppUser(
            "13800000001",
            Set.of(UserRole.BLIND_RUNNER, UserRole.VOLUNTEER),
            UserRole.BLIND_RUNNER
        ));
        BlindRunnerProfile blindProfile = new BlindRunnerProfile(blindRunner, "演示盲人跑者", "有慢跑经验");
        blindProfile.setEmergencyContact(new EmergencyContact("演示紧急联系人", "13900000001"));
        blindRunnerProfileRepository.save(blindProfile);

        AppUser volunteer = userRepository.save(new AppUser(
            "13800000002",
            Set.of(UserRole.BLIND_RUNNER, UserRole.VOLUNTEER),
            UserRole.VOLUNTEER
        ));
        volunteerProfileRepository.save(new VolunteerProfile(
            volunteer,
            "演示志愿者",
            volunteer.getPhoneNumber(),
            VerificationStatus.APPROVED,
            AdminReviewStatus.APPROVED,
            true,
            200
        ));

        RunOrder matchingMorning = new RunOrder(
            blindRunner,
            blindProfile.getNickname(),
            RunOrderStatus.MATCHING,
            demoLocation("上海人民公园北门"),
            "公园慢跑一圈",
            Instant.now().plus(2, ChronoUnit.HOURS)
        );
        RunOrder matchingAfternoon = new RunOrder(
            blindRunner,
            blindProfile.getNickname(),
            RunOrderStatus.MATCHING,
            demoLocation("上海体育场 1 号门"),
            "操场轻松跑",
            Instant.now().plus(5, ChronoUnit.HOURS)
        );
        runOrderRepository.save(matchingMorning);
        runOrderRepository.save(matchingAfternoon);

        RunOrder completed = new RunOrder(
            blindRunner,
            blindProfile.getNickname(),
            RunOrderStatus.IN_PROGRESS,
            demoLocation("世纪公园 7 号门"),
            "湖边跑步路线",
            Instant.now().minus(1, ChronoUnit.DAYS)
        );
        completed.assignVolunteer(volunteer, "演示志愿者");
        completed.markCompleted(Instant.now().minus(20, ChronoUnit.HOURS));
        runOrderRepository.save(completed);
        pointsLedgerRepository.save(new VolunteerPointsLedger(volunteer, completed, 100, "service_completed"));
    }

    private LocationPoint demoLocation(String addressText) {
        return new LocationPoint(31.2304, 121.4737, addressText, LocationSource.DEMO_DEFAULT);
    }
}
