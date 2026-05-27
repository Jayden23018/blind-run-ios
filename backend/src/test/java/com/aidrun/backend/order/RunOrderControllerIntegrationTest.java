package com.aidrun.backend.order;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

@SpringBootTest
@AutoConfigureMockMvc
class RunOrderControllerIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    // --- Helper methods ---

    private String loginAndGetToken(String phone) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/auth/phone-login")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"phoneNumber\":\"" + phone + "\",\"verificationCode\":\"123456\"}"))
            .andExpect(status().isOk())
            .andReturn();
        return JsonPath.read(result.getResponse().getContentAsString(), "$.accessToken");
    }

    private void setupBlindRunnerProfile(String token) throws Exception {
        mockMvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put("/api/profiles/blind-runner")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {
                        "nickname": "测试盲人跑者",
                        "runningExperience": "有经验",
                        "emergencyContact": {
                            "name": "紧急联系人",
                            "phoneNumber": "13900001111"
                        }
                    }
                    """))
            .andExpect(status().isOk());
    }

    private void setupVolunteerProfile(String token) throws Exception {
        mockMvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put("/api/profiles/volunteer")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"nickname\": \"测试志愿者\"}"))
            .andExpect(status().isOk());

        mockMvc.perform(post("/api/volunteer/mock-verification/approve")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk());

        mockMvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch("/api/volunteer/availability")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"isAvailable\": true}"))
            .andExpect(status().isOk());
    }

    private String createMatchingOrder(String token) throws Exception {
        String body = """
            {
                "startLocation": {
                    "latitude": 31.2304,
                    "longitude": 121.4737,
                    "addressText": "测试地点",
                    "source": "device_location"
                },
                "appointmentTime": "%s",
                "destinationText": "目的地"
            }
            """.formatted(java.time.Instant.now().plus(2, java.time.temporal.ChronoUnit.HOURS).toString());

        MvcResult result = mockMvc.perform(post("/api/orders")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
            .andExpect(status().isCreated())
            .andReturn();

        return JsonPath.read(result.getResponse().getContentAsString(), "$.id");
    }

    // --- Test: Create Order ---

    @Test
    void createOrder_success_returns201() throws Exception {
        String token = loginAndGetToken("13911110001");
        setupBlindRunnerProfile(token);

        String body = """
            {
                "startLocation": {
                    "latitude": 31.2304,
                    "longitude": 121.4737,
                    "addressText": "人民公园",
                    "source": "device_location"
                },
                "appointmentTime": "%s",
                "destinationText": "公园跑步",
                "estimatedDurationMinutes": 30,
                "pacePreference": "慢跑"
            }
            """.formatted(java.time.Instant.now().plus(2, java.time.temporal.ChronoUnit.HOURS).toString());

        mockMvc.perform(post("/api/orders")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.status").value("matching"))
            .andExpect(jsonPath("$.blindRunnerNickname").value("测试盲人跑者"))
            .andExpect(jsonPath("$.startLocation.latitude").value(31.2304))
            .andExpect(jsonPath("$.volunteerUserId").isEmpty());
    }

    @Test
    void createOrder_appointmentTooSoon_returns400() throws Exception {
        String token = loginAndGetToken("13911110002");
        setupBlindRunnerProfile(token);

        String body = """
            {
                "startLocation": {
                    "latitude": 31.2304,
                    "longitude": 121.4737,
                    "source": "device_location"
                },
                "appointmentTime": "%s"
            }
            """.formatted(java.time.Instant.now().plus(10, java.time.temporal.ChronoUnit.MINUTES).toString());

        mockMvc.perform(post("/api/orders")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("APPOINTMENT_TOO_SOON"));
    }

    @Test
    void createOrder_profileIncomplete_returns400() throws Exception {
        String token = loginAndGetToken("13911110003");

        String body = """
            {
                "startLocation": {
                    "latitude": 31.2304,
                    "longitude": 121.4737,
                    "source": "device_location"
                },
                "appointmentTime": "%s"
            }
            """.formatted(java.time.Instant.now().plus(2, java.time.temporal.ChronoUnit.HOURS).toString());

        mockMvc.perform(post("/api/orders")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("PROFILE_INCOMPLETE"));
    }

    @Test
    void createOrder_noLocation_returns400() throws Exception {
        String token = loginAndGetToken("13911110004");
        setupBlindRunnerProfile(token);

        String body = """
            {
                "appointmentTime": "%s"
            }
            """.formatted(java.time.Instant.now().plus(2, java.time.temporal.ChronoUnit.HOURS).toString());

        mockMvc.perform(post("/api/orders")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(body))
            .andExpect(status().isBadRequest());
    }

    // --- Test: Accept Order ---

    @Test
    void acceptOrder_matchingOrder_returns200() throws Exception {
        String brToken = loginAndGetToken("13911110010");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110011");
        setupVolunteerProfile(volToken);

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("accepted"))
            .andExpect(jsonPath("$.volunteerNickname").value("测试志愿者"))
            .andExpect(jsonPath("$.acceptedAt").isNotEmpty());
    }

    @Test
    void acceptOrder_alreadyAccepted_returns409() throws Exception {
        String brToken = loginAndGetToken("13911110020");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String vol1Token = loginAndGetToken("13911110021");
        setupVolunteerProfile(vol1Token);

        String vol2Token = loginAndGetToken("13911110022");
        setupVolunteerProfile(vol2Token);

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + vol1Token))
            .andExpect(status().isOk());

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + vol2Token))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("ORDER_ALREADY_ACCEPTED"));
    }

    @Test
    void acceptOrder_volunteerNotApproved_returnsForbidden() throws Exception {
        String brToken = loginAndGetToken("13911110030");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110031");
        // Set up profile but DO NOT approve
        mockMvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put("/api/profiles/volunteer")
                .header("Authorization", "Bearer " + volToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"nickname\": \"未认证志愿者\"}"))
            .andExpect(status().isOk());

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isForbidden())
            .andExpect(jsonPath("$.code").value("VOLUNTEER_NOT_APPROVED"));
    }

    @Test
    void acceptOrder_volunteerNotAvailable_returnsForbidden() throws Exception {
        String brToken = loginAndGetToken("13911110040");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110041");
        // Approve but do NOT toggle availability
        mockMvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put("/api/profiles/volunteer")
                .header("Authorization", "Bearer " + volToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"nickname\": \"志愿者\"}"))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/volunteer/mock-verification/approve")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isForbidden())
            .andExpect(jsonPath("$.code").value("VOLUNTEER_NOT_AVAILABLE"));
    }

    // --- Test: Full Flow ---

    @Test
    void fullFlow_matching_to_completed() throws Exception {
        String brToken = loginAndGetToken("13911110050");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110051");
        setupVolunteerProfile(volToken);

        // Accept
        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("accepted"));

        // Arrive
        mockMvc.perform(post("/api/orders/" + orderId + "/arrive")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("arrived"))
            .andExpect(jsonPath("$.arrivedAt").isNotEmpty());

        // Start (blind runner confirms)
        mockMvc.perform(post("/api/orders/" + orderId + "/confirm-start")
                .header("Authorization", "Bearer " + brToken))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("in_progress"))
            .andExpect(jsonPath("$.startedAt").isNotEmpty());

        // Complete (volunteer)
        mockMvc.perform(post("/api/orders/" + orderId + "/complete")
                .header("Authorization", "Bearer " + volToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"summaryText\": \"服务顺利完成\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("completed"))
            .andExpect(jsonPath("$.completedAt").isNotEmpty());
    }

    // --- Test: Cancel ---

    @Test
    void cancelOrder_fromMatching_success() throws Exception {
        String brToken = loginAndGetToken("13911110060");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        mockMvc.perform(post("/api/orders/" + orderId + "/cancel")
                .header("Authorization", "Bearer " + brToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {
                        "cancelledReason": "time_conflict"
                    }
                    """))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("cancelled"))
            .andExpect(jsonPath("$.cancelledAt").isNotEmpty());
    }

    @Test
    void cancelOrder_fromInProgress_returns409() throws Exception {
        String brToken = loginAndGetToken("13911110070");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110071");
        setupVolunteerProfile(volToken);

        // Move to in_progress
        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/orders/" + orderId + "/arrive")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/orders/" + orderId + "/confirm-start")
                .header("Authorization", "Bearer " + brToken))
            .andExpect(status().isOk());

        // Attempt cancel from in_progress
        mockMvc.perform(post("/api/orders/" + orderId + "/cancel")
                .header("Authorization", "Bearer " + brToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {
                        "cancelledReason": "temporary_issue"
                    }
                    """))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("INVALID_ORDER_STATUS"));
    }

    // --- Test: Emergency ---

    @Test
    void emergency_fromInProgress_success() throws Exception {
        String brToken = loginAndGetToken("13911110080");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110081");
        setupVolunteerProfile(volToken);

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/orders/" + orderId + "/arrive")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/orders/" + orderId + "/confirm-start")
                .header("Authorization", "Bearer " + brToken))
            .andExpect(status().isOk());

        mockMvc.perform(post("/api/orders/" + orderId + "/emergency")
                .header("Authorization", "Bearer " + brToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"note\": \"需要帮助\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("emergency"))
            .andExpect(jsonPath("$.emergencyAt").isNotEmpty());
    }

    @Test
    void emergency_isTerminal_cannotTransition() throws Exception {
        String brToken = loginAndGetToken("13911110090");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110091");
        setupVolunteerProfile(volToken);

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());

        // Trigger emergency
        mockMvc.perform(post("/api/orders/" + orderId + "/emergency")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("emergency"));

        // Try to complete after emergency - should fail
        mockMvc.perform(post("/api/orders/" + orderId + "/complete")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("INVALID_ORDER_STATUS"));

        // Try to cancel after emergency - should fail
        mockMvc.perform(post("/api/orders/" + orderId + "/cancel")
                .header("Authorization", "Bearer " + volToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {
                        "cancelledReason": "temporary_issue"
                    }
                    """))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("INVALID_ORDER_STATUS"));
    }

    // --- Test: Emergency - Extended Coverage ---

    @Test
    void emergency_fromAccepted_success() throws Exception {
        String brToken = loginAndGetToken("13911110200");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110201");
        setupVolunteerProfile(volToken);

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());

        // Volunteer triggers emergency from accepted state
        mockMvc.perform(post("/api/orders/" + orderId + "/emergency")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("emergency"))
            .andExpect(jsonPath("$.emergencyAt").isNotEmpty())
            .andExpect(jsonPath("$.emergencyEvent.triggeredByRole").value("volunteer"))
            .andExpect(jsonPath("$.emergencyEvent.previousStatus").value("accepted"));
    }

    @Test
    void emergency_fromArrived_success() throws Exception {
        String brToken = loginAndGetToken("13911110210");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110211");
        setupVolunteerProfile(volToken);

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/orders/" + orderId + "/arrive")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());

        // Blind runner triggers emergency from arrived state with note
        mockMvc.perform(post("/api/orders/" + orderId + "/emergency")
                .header("Authorization", "Bearer " + brToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"note\": \"遇到紧急情况\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("emergency"))
            .andExpect(jsonPath("$.emergencyAt").isNotEmpty())
            .andExpect(jsonPath("$.emergencyEvent.triggeredByRole").value("blind_runner"))
            .andExpect(jsonPath("$.emergencyEvent.previousStatus").value("arrived"))
            .andExpect(jsonPath("$.emergencyEvent.note").value("遇到紧急情况"));
    }

    @Test
    void emergency_fromInProgress_validatesEventData() throws Exception {
        String brToken = loginAndGetToken("13911110220");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110221");
        setupVolunteerProfile(volToken);

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/orders/" + orderId + "/arrive")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/orders/" + orderId + "/confirm-start")
                .header("Authorization", "Bearer " + brToken))
            .andExpect(status().isOk());

        // Blind runner triggers emergency from in_progress - validate all event fields
        mockMvc.perform(post("/api/orders/" + orderId + "/emergency")
                .header("Authorization", "Bearer " + brToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"note\": \"需要紧急帮助\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("emergency"))
            .andExpect(jsonPath("$.emergencyAt").isNotEmpty())
            .andExpect(jsonPath("$.emergencyEvent.id").isNotEmpty())
            .andExpect(jsonPath("$.emergencyEvent.triggeredByRole").value("blind_runner"))
            .andExpect(jsonPath("$.emergencyEvent.previousStatus").value("in_progress"))
            .andExpect(jsonPath("$.emergencyEvent.note").value("需要紧急帮助"))
            .andExpect(jsonPath("$.emergencyEvent.createdAt").isNotEmpty());
    }

    @Test
    void emergency_fromCompleted_returns409() throws Exception {
        String brToken = loginAndGetToken("13911110230");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110231");
        setupVolunteerProfile(volToken);

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/orders/" + orderId + "/arrive")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/orders/" + orderId + "/confirm-start")
                .header("Authorization", "Bearer " + brToken))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/orders/" + orderId + "/complete")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());

        // Completed order cannot trigger emergency
        mockMvc.perform(post("/api/orders/" + orderId + "/emergency")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("INVALID_ORDER_STATUS"));
    }

    @Test
    void emergency_fromCancelled_returns409() throws Exception {
        String brToken = loginAndGetToken("13911110240");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        // Cancel the order from matching state
        mockMvc.perform(post("/api/orders/" + orderId + "/cancel")
                .header("Authorization", "Bearer " + brToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"cancelledReason\": \"temporary_issue\"}"))
            .andExpect(status().isOk());

        // Cancelled order cannot trigger emergency
        mockMvc.perform(post("/api/orders/" + orderId + "/emergency")
                .header("Authorization", "Bearer " + brToken))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("INVALID_ORDER_STATUS"));
    }

    @Test
    void emergency_fromMatching_returns409() throws Exception {
        String brToken = loginAndGetToken("13911110250");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        // Matching order cannot trigger emergency
        mockMvc.perform(post("/api/orders/" + orderId + "/emergency")
                .header("Authorization", "Bearer " + brToken))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("INVALID_ORDER_STATUS"));
    }

    @Test
    void emergency_reTriggered_returns409() throws Exception {
        String brToken = loginAndGetToken("13911110260");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110261");
        setupVolunteerProfile(volToken);

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());

        // First emergency succeeds
        mockMvc.perform(post("/api/orders/" + orderId + "/emergency")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("emergency"));

        // Second emergency attempt fails - emergency is terminal
        mockMvc.perform(post("/api/orders/" + orderId + "/emergency")
                .header("Authorization", "Bearer " + brToken))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("INVALID_ORDER_STATUS"));
    }

    @Test
    void emergency_isTerminal_cannotArrive() throws Exception {
        String brToken = loginAndGetToken("13911110270");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110271");
        setupVolunteerProfile(volToken);

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());

        // Trigger emergency from accepted
        mockMvc.perform(post("/api/orders/" + orderId + "/emergency")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());

        // Cannot arrive after emergency
        mockMvc.perform(post("/api/orders/" + orderId + "/arrive")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("INVALID_ORDER_STATUS"));
    }

    @Test
    void emergency_isTerminal_cannotConfirmStart() throws Exception {
        String brToken = loginAndGetToken("13911110280");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110281");
        setupVolunteerProfile(volToken);

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/orders/" + orderId + "/arrive")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());

        // Trigger emergency from arrived
        mockMvc.perform(post("/api/orders/" + orderId + "/emergency")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());

        // Cannot confirm-start after emergency
        mockMvc.perform(post("/api/orders/" + orderId + "/confirm-start")
                .header("Authorization", "Bearer " + brToken))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("INVALID_ORDER_STATUS"));
    }

    @Test
    void emergency_byNonParticipant_returnsForbidden() throws Exception {
        String brToken = loginAndGetToken("13911110290");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110291");
        setupVolunteerProfile(volToken);

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());

        // A different user (not participant) tries to trigger emergency
        String outsiderToken = loginAndGetToken("13911110292");
        setupVolunteerProfile(outsiderToken);

        mockMvc.perform(post("/api/orders/" + orderId + "/emergency")
                .header("Authorization", "Bearer " + outsiderToken))
            .andExpect(status().isForbidden());
    }

    // --- Test: Complete + Points ---

    @Test
    void completeOrder_volunteerGets100Points() throws Exception {
        String brToken = loginAndGetToken("13911110100");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110101");
        setupVolunteerProfile(volToken);

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/orders/" + orderId + "/arrive")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/orders/" + orderId + "/confirm-start")
                .header("Authorization", "Bearer " + brToken))
            .andExpect(status().isOk());

        mockMvc.perform(post("/api/orders/" + orderId + "/complete")
                .header("Authorization", "Bearer " + volToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"summaryText\": \"完成\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("completed"));

        // Verify volunteer points increased (check profile)
        mockMvc.perform(get("/api/users/me")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.volunteerProfile.pointsBalance").value(100));
    }

    // --- Test: Rating ---

    @Test
    void rating_afterCompleted_success() throws Exception {
        String brToken = loginAndGetToken("13911110110");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110111");
        setupVolunteerProfile(volToken);

        mockMvc.perform(post("/api/orders/" + orderId + "/accept")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/orders/" + orderId + "/arrive")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/orders/" + orderId + "/confirm-start")
                .header("Authorization", "Bearer " + brToken))
            .andExpect(status().isOk());
        mockMvc.perform(post("/api/orders/" + orderId + "/complete")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk());

        mockMvc.perform(post("/api/orders/" + orderId + "/rating")
                .header("Authorization", "Bearer " + brToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"stars\": 5, \"comment\": \"非常好\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.stars").value(5))
            .andExpect(jsonPath("$.comment").value("非常好"));
    }

    @Test
    void rating_beforeCompleted_returns409() throws Exception {
        String brToken = loginAndGetToken("13911110120");
        setupBlindRunnerProfile(brToken);
        String orderId = createMatchingOrder(brToken);

        mockMvc.perform(post("/api/orders/" + orderId + "/rating")
                .header("Authorization", "Bearer " + brToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"stars\": 5}"))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("INVALID_ORDER_STATUS"));
    }

    // --- Test: Available orders hide phone ---

    @Test
    void availableOrders_hidesBlindRunnerPhone() throws Exception {
        String brToken = loginAndGetToken("13911110130");
        setupBlindRunnerProfile(brToken);
        createMatchingOrder(brToken);

        String volToken = loginAndGetToken("13911110131");
        setupVolunteerProfile(volToken);

        mockMvc.perform(get("/api/orders/available")
                .header("Authorization", "Bearer " + volToken))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$[0].blindRunnerPhone").isEmpty());
    }

    // --- Test: My Orders ---

    @Test
    void myOrders_returnsBothRoles() throws Exception {
        String brToken = loginAndGetToken("13911110140");
        setupBlindRunnerProfile(brToken);
        createMatchingOrder(brToken);

        mockMvc.perform(get("/api/orders/my")
                .header("Authorization", "Bearer " + brToken))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$").isArray())
            .andExpect(jsonPath("$.length()").value(org.hamcrest.Matchers.greaterThanOrEqualTo(1)));
    }
}
