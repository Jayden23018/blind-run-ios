package com.aidrun.backend.profile;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

@SpringBootTest
@AutoConfigureMockMvc
class ProfileControllerIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

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

    // ==================== Blind Runner Profile Tests ====================

    @Test
    void createBlindRunnerProfile_validRequest_returns200() throws Exception {
        String token = loginAndGetToken("13900100001");

        mockMvc.perform(put("/api/profiles/blind-runner")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {
                      "nickname": "测试盲人",
                      "runningExperience": "有慢跑经验",
                      "emergencyContact": {
                        "name": "紧急联系人",
                        "phoneNumber": "13800001111"
                      }
                    }
                    """))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.nickname").value("测试盲人"))
            .andExpect(jsonPath("$.runningExperience").value("有慢跑经验"))
            .andExpect(jsonPath("$.emergencyContact.name").value("紧急联系人"))
            .andExpect(jsonPath("$.emergencyContact.phoneNumber").value("13800001111"))
            .andExpect(jsonPath("$.userId").isNotEmpty())
            .andExpect(jsonPath("$.id").isNotEmpty())
            .andExpect(jsonPath("$.createdAt").isNotEmpty())
            .andExpect(jsonPath("$.updatedAt").isNotEmpty());
    }

    @Test
    void updateBlindRunnerProfile_existingProfile_returns200WithUpdatedData() throws Exception {
        String token = loginAndGetToken("13900100002");

        // Create first
        mockMvc.perform(put("/api/profiles/blind-runner")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {
                      "nickname": "初始昵称",
                      "emergencyContact": {
                        "name": "联系人A",
                        "phoneNumber": "13800002222"
                      }
                    }
                    """))
            .andExpect(status().isOk());

        // Update
        mockMvc.perform(put("/api/profiles/blind-runner")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {
                      "nickname": "更新后昵称",
                      "runningExperience": "新增经验",
                      "emergencyContact": {
                        "name": "联系人B",
                        "phoneNumber": "13800003333"
                      }
                    }
                    """))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.nickname").value("更新后昵称"))
            .andExpect(jsonPath("$.runningExperience").value("新增经验"))
            .andExpect(jsonPath("$.emergencyContact.name").value("联系人B"))
            .andExpect(jsonPath("$.emergencyContact.phoneNumber").value("13800003333"));
    }

    @Test
    void createBlindRunnerProfile_missingNickname_returns400() throws Exception {
        String token = loginAndGetToken("13900100003");

        mockMvc.perform(put("/api/profiles/blind-runner")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {
                      "emergencyContact": {
                        "name": "联系人",
                        "phoneNumber": "13800004444"
                      }
                    }
                    """))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));
    }

    @Test
    void createBlindRunnerProfile_missingEmergencyContact_returns400() throws Exception {
        String token = loginAndGetToken("13900100004");

        mockMvc.perform(put("/api/profiles/blind-runner")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {
                      "nickname": "测试"
                    }
                    """))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));
    }

    @Test
    void createBlindRunnerProfile_invalidEmergencyPhone_returns400() throws Exception {
        String token = loginAndGetToken("13900100005");

        mockMvc.perform(put("/api/profiles/blind-runner")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {
                      "nickname": "测试",
                      "emergencyContact": {
                        "name": "联系人",
                        "phoneNumber": "12345"
                      }
                    }
                    """))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));
    }

    @Test
    void createBlindRunnerProfile_withoutToken_returns401() throws Exception {
        mockMvc.perform(put("/api/profiles/blind-runner")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {
                      "nickname": "测试",
                      "emergencyContact": {
                        "name": "联系人",
                        "phoneNumber": "13800005555"
                      }
                    }
                    """))
            .andExpect(status().isUnauthorized());
    }

    @Test
    void createBlindRunnerProfile_nullRunningExperience_returns200() throws Exception {
        String token = loginAndGetToken("13900100006");

        mockMvc.perform(put("/api/profiles/blind-runner")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {
                      "nickname": "测试盲人",
                      "emergencyContact": {
                        "name": "紧急联系人",
                        "phoneNumber": "13800006666"
                      }
                    }
                    """))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.nickname").value("测试盲人"))
            .andExpect(jsonPath("$.runningExperience").doesNotExist());
    }

    // ==================== Volunteer Profile Tests ====================

    @Test
    void createVolunteerProfile_validRequest_returns200WithDefaults() throws Exception {
        String token = loginAndGetToken("13900100007");

        mockMvc.perform(put("/api/profiles/volunteer")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {
                      "nickname": "测试志愿者"
                    }
                    """))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.nickname").value("测试志愿者"))
            .andExpect(jsonPath("$.phoneNumber").value("13900100007"))
            .andExpect(jsonPath("$.verificationStatus").value("not_submitted"))
            .andExpect(jsonPath("$.adminReviewStatus").value("not_submitted"))
            .andExpect(jsonPath("$.isAvailable").value(false))
            .andExpect(jsonPath("$.pointsBalance").value(0))
            .andExpect(jsonPath("$.userId").isNotEmpty())
            .andExpect(jsonPath("$.id").isNotEmpty());
    }

    @Test
    void updateVolunteerProfile_existingProfile_returns200() throws Exception {
        String token = loginAndGetToken("13900100008");

        // Create first
        mockMvc.perform(put("/api/profiles/volunteer")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"nickname": "初始昵称"}
                    """))
            .andExpect(status().isOk());

        // Update
        mockMvc.perform(put("/api/profiles/volunteer")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"nickname": "更新后昵称"}
                    """))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.nickname").value("更新后昵称"));
    }

    @Test
    void createVolunteerProfile_missingNickname_returns400() throws Exception {
        String token = loginAndGetToken("13900100009");

        mockMvc.perform(put("/api/profiles/volunteer")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {}
                    """))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));
    }

    @Test
    void createVolunteerProfile_withoutToken_returns401() throws Exception {
        mockMvc.perform(put("/api/profiles/volunteer")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"nickname": "测试"}
                    """))
            .andExpect(status().isUnauthorized());
    }
}
