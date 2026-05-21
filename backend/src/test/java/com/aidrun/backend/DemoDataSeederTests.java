package com.aidrun.backend;

import static org.assertj.core.api.Assertions.assertThat;

import com.aidrun.backend.order.RunOrderRepository;
import com.aidrun.backend.order.RunOrderStatus;
import com.aidrun.backend.profile.BlindRunnerProfileRepository;
import com.aidrun.backend.profile.VolunteerProfileRepository;
import com.aidrun.backend.user.AppUserRepository;
import com.aidrun.backend.volunteer.VolunteerPointsLedgerRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
class DemoDataSeederTests {

    @Autowired
    private AppUserRepository userRepository;

    @Autowired
    private BlindRunnerProfileRepository blindRunnerProfileRepository;

    @Autowired
    private VolunteerProfileRepository volunteerProfileRepository;

    @Autowired
    private RunOrderRepository runOrderRepository;

    @Autowired
    private VolunteerPointsLedgerRepository pointsLedgerRepository;

    @Test
    void seedCreatesRequiredDemoRecords() {
        assertThat(userRepository.count()).isGreaterThanOrEqualTo(2);
        assertThat(blindRunnerProfileRepository.findAll())
            .anySatisfy(profile -> assertThat(profile.getEmergencyContact()).isNotNull());
        assertThat(volunteerProfileRepository.findAll())
            .anySatisfy(profile -> {
                assertThat(profile.isAvailable()).isTrue();
                assertThat(profile.getVerificationStatus().getWireValue()).isEqualTo("approved");
                assertThat(profile.getAdminReviewStatus().getWireValue()).isEqualTo("approved");
            });
        assertThat(runOrderRepository.countByStatus(RunOrderStatus.MATCHING)).isGreaterThanOrEqualTo(2);
        assertThat(runOrderRepository.countByStatus(RunOrderStatus.COMPLETED)).isGreaterThanOrEqualTo(1);
        assertThat(pointsLedgerRepository.count()).isGreaterThanOrEqualTo(1);
    }
}
