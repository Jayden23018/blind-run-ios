package com.aidrun.backend.user;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.aidrun.backend.location.LocationPoint;
import com.aidrun.backend.location.LocationSource;
import com.aidrun.backend.order.RunOrder;
import com.aidrun.backend.order.RunOrderRepository;
import com.aidrun.backend.order.RunOrderStatus;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

@SpringBootTest
@AutoConfigureMockMvc
class UserControllerIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private AppUserRepository appUserRepository;

    @Autowired
    private RunOrderRepository runOrderRepository;

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

    @Test
    void getMe_withValidToken_returns200() throws Exception {
        String token = loginAndGetToken("13900005555");

        mockMvc.perform(get("/api/users/me")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.user.phoneNumber").value("13900005555"))
            .andExpect(jsonPath("$.user.id").isNotEmpty())
            .andExpect(jsonPath("$.user.roles").isArray());
    }

    @Test
    void getMe_withBlindRunnerProfile_returnsContractFields() throws Exception {
        String token = loginAndGetToken("13800000001");

        mockMvc.perform(get("/api/users/me")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.blindRunnerProfile.userId").isNotEmpty())
            .andExpect(jsonPath("$.blindRunnerProfile.nickname").value("演示盲人跑者"))
            .andExpect(jsonPath("$.blindRunnerProfile.runningExperience").value("有慢跑经验"))
            .andExpect(jsonPath("$.blindRunnerProfile.emergencyContact.name").value("演示紧急联系人"))
            .andExpect(jsonPath("$.blindRunnerProfile.createdAt").isNotEmpty())
            .andExpect(jsonPath("$.blindRunnerProfile.updatedAt").isNotEmpty());
    }

    @Test
    void getMe_withVolunteerProfile_returnsContractFields() throws Exception {
        String token = loginAndGetToken("13800000002");

        mockMvc.perform(get("/api/users/me")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.volunteerProfile.userId").isNotEmpty())
            .andExpect(jsonPath("$.volunteerProfile.nickname").value("演示志愿者"))
            .andExpect(jsonPath("$.volunteerProfile.phoneNumber").value("13800000002"))
            .andExpect(jsonPath("$.volunteerProfile.verificationStatus").value("approved"))
            .andExpect(jsonPath("$.volunteerProfile.adminReviewStatus").value("approved"))
            .andExpect(jsonPath("$.volunteerProfile.isAvailable").value(true))
            .andExpect(jsonPath("$.volunteerProfile.pointsBalance").value(200));
    }

    @Test
    void getMe_withoutToken_returns401() throws Exception {
        mockMvc.perform(get("/api/users/me"))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));
    }

    @Test
    void getMe_withInvalidToken_returns401() throws Exception {
        mockMvc.perform(get("/api/users/me")
                .header("Authorization", "Bearer invalid-garbage-token"))
            .andExpect(status().isUnauthorized());
    }

    @Test
    void switchRole_toVolunteer_succeeds() throws Exception {
        String token = loginAndGetToken("13900004444");

        mockMvc.perform(patch("/api/users/me/active-role")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"activeRole":"volunteer"}
                    """))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.activeRole").value("volunteer"));
    }

    @Test
    void switchRole_toBlindRunner_succeeds() throws Exception {
        String token = loginAndGetToken("13900003333");

        mockMvc.perform(patch("/api/users/me/active-role")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"activeRole":"blind_runner"}
                    """))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.activeRole").value("blind_runner"));
    }

    @Test
    void switchRole_withActiveOrder_returns409() throws Exception {
        String token = loginAndGetToken("13900002222");

        // Find the user to create an active order
        AppUser user = appUserRepository.findByPhoneNumber("13900002222").orElseThrow();

        // Create an order in ACCEPTED status
        LocationPoint startLocation = new LocationPoint(
            39.9042,
            116.4074,
            "北京天安门",
            LocationSource.DEMO_DEFAULT
        );
        RunOrder order = new RunOrder(
            user, "测试盲人跑者", RunOrderStatus.ACCEPTED,
            startLocation, "终点", Instant.now().plusSeconds(3600)
        );
        runOrderRepository.save(order);

        mockMvc.perform(patch("/api/users/me/active-role")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"activeRole":"volunteer"}
                    """))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.code").value("ACTIVE_ORDER_ROLE_SWITCH_BLOCKED"));
    }

    @Test
    void switchRole_withCompletedOrder_succeeds() throws Exception {
        String token = loginAndGetToken("13900001111");

        AppUser user = appUserRepository.findByPhoneNumber("13900001111").orElseThrow();

        // Create only a completed order
        LocationPoint startLocation = new LocationPoint(
            39.9042,
            116.4074,
            "北京天安门",
            LocationSource.DEMO_DEFAULT
        );
        RunOrder order = new RunOrder(
            user, "测试盲人跑者", RunOrderStatus.COMPLETED,
            startLocation, "终点", Instant.now().plusSeconds(3600)
        );
        runOrderRepository.save(order);

        mockMvc.perform(patch("/api/users/me/active-role")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"activeRole":"blind_runner"}
                    """))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.activeRole").value("blind_runner"));
    }

    @Test
    void switchRole_withoutToken_returns401() throws Exception {
        mockMvc.perform(patch("/api/users/me/active-role")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"activeRole":"volunteer"}
                    """))
            .andExpect(status().isUnauthorized());
    }
}
