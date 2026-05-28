package com.aidrun.backend.volunteer;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.aidrun.backend.user.AppUser;
import com.aidrun.backend.user.AppUserRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

@SpringBootTest
@AutoConfigureMockMvc
class VolunteerControllerIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private AppUserRepository appUserRepository;

    @Autowired
    private VolunteerService volunteerService;

    private String loginAndGetToken(String phoneNumber) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/auth/phone-login")
                .contentType(MediaType.APPLICATION_JSON)
                .content(String.format(
                    """
                    {"phoneNumber":"%s","verificationCode":"123456"}
                    """, phoneNumber)))
            .andExpect(status().isOk())
            .andReturn();

        return com.jayway.jsonpath.JsonPath
            .read(result.getResponse().getContentAsString(), "$.accessToken");
    }

    private void createVolunteerProfile(String token) throws Exception {
        mockMvc.perform(put("/api/profiles/volunteer")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"nickname": "测试志愿者"}
                    """))
            .andExpect(status().isOk());
    }

    // ==================== Mock Verification Tests ====================

    @Test
    void mockVerification_withVolunteerProfile_setsBothStatusesApproved() throws Exception {
        String token = loginAndGetToken("13900200001");
        createVolunteerProfile(token);

        mockMvc.perform(post("/api/volunteer/mock-verification/approve")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.verificationStatus").value("approved"))
            .andExpect(jsonPath("$.adminReviewStatus").value("approved"));
    }

    @Test
    void mockVerification_withoutProfile_returns400ProfileIncomplete() throws Exception {
        String token = loginAndGetToken("13900200002");

        mockMvc.perform(post("/api/volunteer/mock-verification/approve")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("PROFILE_INCOMPLETE"));
    }

    @Test
    void mockVerification_withoutToken_returns401() throws Exception {
        mockMvc.perform(post("/api/volunteer/mock-verification/approve"))
            .andExpect(status().isUnauthorized());
    }

    @Test
    void mockVerification_calledTwice_isIdempotent() throws Exception {
        String token = loginAndGetToken("13900200003");
        createVolunteerProfile(token);

        // First call
        mockMvc.perform(post("/api/volunteer/mock-verification/approve")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.verificationStatus").value("approved"));

        // Second call - same result
        mockMvc.perform(post("/api/volunteer/mock-verification/approve")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.verificationStatus").value("approved"))
            .andExpect(jsonPath("$.adminReviewStatus").value("approved"));
    }

    // ==================== Availability Tests ====================

    @Test
    void availability_turnOnAfterApproval_returns200() throws Exception {
        String token = loginAndGetToken("13900200004");
        createVolunteerProfile(token);

        // Approve first
        mockMvc.perform(post("/api/volunteer/mock-verification/approve")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk());

        // Toggle on
        mockMvc.perform(put("/api/volunteer/profile")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"isAvailable": true}
                    """))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.isAvailable").value(true));
    }

    @Test
    void availability_turnOff_returns200() throws Exception {
        String token = loginAndGetToken("13900200005");
        createVolunteerProfile(token);

        // Approve and turn on first
        mockMvc.perform(post("/api/volunteer/mock-verification/approve")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk());

        mockMvc.perform(put("/api/volunteer/profile")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"isAvailable": true}
                    """))
            .andExpect(status().isOk());

        // Toggle off
        mockMvc.perform(put("/api/volunteer/profile")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"isAvailable": false}
                    """))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.isAvailable").value(false));
    }

    @Test
    void availability_withoutApproval_returns403VolunteerNotApproved() throws Exception {
        String token = loginAndGetToken("13900200006");
        createVolunteerProfile(token);

        mockMvc.perform(put("/api/volunteer/profile")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"isAvailable": true}
                    """))
            .andExpect(status().isForbidden())
            .andExpect(jsonPath("$.code").value("VOLUNTEER_NOT_APPROVED"));
    }

    @Test
    void availability_withoutProfile_returns400ProfileIncomplete() throws Exception {
        String token = loginAndGetToken("13900200007");

        mockMvc.perform(put("/api/volunteer/profile")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"isAvailable": true}
                    """))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("PROFILE_INCOMPLETE"));
    }

    @Test
    void availability_withoutToken_returns401() throws Exception {
        mockMvc.perform(put("/api/volunteer/profile")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"isAvailable": true}
                    """))
            .andExpect(status().isUnauthorized());
    }

    @Test
    void profile_updateNickname_returns200() throws Exception {
        String token = loginAndGetToken("13900200008");
        createVolunteerProfile(token);

        mockMvc.perform(put("/api/volunteer/profile")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"nickname": "新昵称"}
                    """))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.nickname").value("新昵称"));
    }

    // ==================== Volunteer Acceptance Validation Tests ====================

    @Test
    void validateCanAcceptOrder_notApproved_throwsVolunteerNotApproved() throws Exception {
        String token = loginAndGetToken("13900200009");
        createVolunteerProfile(token);

        AppUser user = appUserRepository.findByPhoneNumber("13900200009").orElseThrow();

        try {
            volunteerService.validateVolunteerCanAcceptOrder(user);
            org.junit.jupiter.api.Assertions.fail("Expected ApiException");
        } catch (com.aidrun.backend.common.error.ApiException e) {
            org.junit.jupiter.api.Assertions.assertEquals(
                com.aidrun.backend.common.error.ErrorCode.VOLUNTEER_NOT_APPROVED, e.getCode());
        }
    }

    @Test
    void validateCanAcceptOrder_notAvailable_throwsVolunteerNotAvailable() throws Exception {
        String token = loginAndGetToken("13900200010");
        createVolunteerProfile(token);

        // Approve but keep isAvailable = false
        mockMvc.perform(post("/api/volunteer/mock-verification/approve")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk());

        AppUser user = appUserRepository.findByPhoneNumber("13900200010").orElseThrow();

        try {
            volunteerService.validateVolunteerCanAcceptOrder(user);
            org.junit.jupiter.api.Assertions.fail("Expected ApiException");
        } catch (com.aidrun.backend.common.error.ApiException e) {
            org.junit.jupiter.api.Assertions.assertEquals(
                com.aidrun.backend.common.error.ErrorCode.VOLUNTEER_NOT_AVAILABLE, e.getCode());
        }
    }
}
