package com.aidrun.backend;

import static org.assertj.core.api.Assertions.assertThat;

import com.aidrun.backend.order.CancelledBy;
import com.aidrun.backend.order.RunOrderStatus;
import com.aidrun.backend.profile.AdminReviewStatus;
import com.aidrun.backend.profile.VerificationStatus;
import com.aidrun.backend.user.UserRole;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Arrays;
import org.junit.jupiter.api.Test;

class EnumWireValueTests {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void userRoleUsesLowerSnakeCaseWireValue() throws JsonProcessingException {
        assertThat(objectMapper.writeValueAsString(UserRole.BLIND_RUNNER)).isEqualTo("\"blind_runner\"");
        assertThat(objectMapper.readValue("\"volunteer\"", UserRole.class)).isEqualTo(UserRole.VOLUNTEER);
    }

    @Test
    void profileStatusesUseLowerSnakeCaseWireValues() throws JsonProcessingException {
        assertThat(objectMapper.writeValueAsString(VerificationStatus.NOT_SUBMITTED)).isEqualTo("\"not_submitted\"");
        assertThat(objectMapper.writeValueAsString(AdminReviewStatus.APPROVED)).isEqualTo("\"approved\"");
    }

    @Test
    void runOrderStatusContainsOnlyMvpStatuses() throws JsonProcessingException {
        assertThat(Arrays.stream(RunOrderStatus.values()).map(RunOrderStatus::getWireValue))
            .containsExactly("matching", "accepted", "arrived", "in_progress", "completed", "cancelled", "emergency")
            .doesNotContain("submitted", "contacted", "expired");
        assertThat(objectMapper.writeValueAsString(RunOrderStatus.IN_PROGRESS)).isEqualTo("\"in_progress\"");
    }

    @Test
    void cancelledByMatchesCancellationActorWireValues() throws JsonProcessingException {
        assertThat(objectMapper.writeValueAsString(CancelledBy.BLIND_RUNNER)).isEqualTo("\"blind_runner\"");
        assertThat(objectMapper.readValue("\"volunteer\"", CancelledBy.class)).isEqualTo(CancelledBy.VOLUNTEER);
    }
}
