package com.aidrun.backend.auth;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
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
class AuthControllerIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void phoneLogin_withCorrectCode_returnsTokenAndUser() throws Exception {
        MvcResult result = mockMvc.perform(post("/api/auth/phone-login")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"phoneNumber":"13900009999","verificationCode":"123456"}
                    """))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.accessToken").isNotEmpty())
            .andExpect(jsonPath("$.tokenType").value("Bearer"))
            .andExpect(jsonPath("$.user.phoneNumber").value("13900009999"))
            .andExpect(jsonPath("$.user.activeRole").isEmpty())
            .andExpect(jsonPath("$.user.roles").isArray())
            .andReturn();

        String accessToken = com.jayway.jsonpath.JsonPath
            .read(result.getResponse().getContentAsString(), "$.accessToken");
        org.junit.jupiter.api.Assertions.assertEquals(3, accessToken.split("\\.").length);
    }

    @Test
    void phoneLogin_withWrongCode_returns400() throws Exception {
        mockMvc.perform(post("/api/auth/phone-login")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"phoneNumber":"13900009999","verificationCode":"999999"}
                    """))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("INVALID_VERIFICATION_CODE"))
            .andExpect(jsonPath("$.message").value("验证码错误"));
    }

    @Test
    void phoneLogin_existingUser_returnsSameUserId() throws Exception {
        MvcResult first = mockMvc.perform(post("/api/auth/phone-login")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"phoneNumber":"13900008888","verificationCode":"123456"}
                    """))
            .andExpect(status().isOk())
            .andReturn();

        String firstUserId = com.jayway.jsonpath.JsonPath
            .read(first.getResponse().getContentAsString(), "$.user.id");

        MvcResult second = mockMvc.perform(post("/api/auth/phone-login")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"phoneNumber":"13900008888","verificationCode":"123456"}
                    """))
            .andExpect(status().isOk())
            .andReturn();

        String secondUserId = com.jayway.jsonpath.JsonPath
            .read(second.getResponse().getContentAsString(), "$.user.id");

        org.junit.jupiter.api.Assertions.assertEquals(firstUserId, secondUserId);
    }

    @Test
    void phoneLogin_newUser_createsBothRoles() throws Exception {
        mockMvc.perform(post("/api/auth/phone-login")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"phoneNumber":"13900007777","verificationCode":"123456"}
                    """))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.user.roles.length()").value(2));
    }

    @Test
    void phoneLogin_blankPhone_returns400() throws Exception {
        mockMvc.perform(post("/api/auth/phone-login")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"phoneNumber":"","verificationCode":"123456"}
                    """))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));
    }

    @Test
    void phoneLogin_tooLongPhone_returns400() throws Exception {
        mockMvc.perform(post("/api/auth/phone-login")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"phoneNumber":"139000099999","verificationCode":"123456"}
                    """))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));
    }

    @Test
    void phoneLogin_tooShortPhone_returns400() throws Exception {
        mockMvc.perform(post("/api/auth/phone-login")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"phoneNumber":"1390000999","verificationCode":"123456"}
                    """))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));
    }

    @Test
    void phoneLogin_nonNumericPhone_returns400() throws Exception {
        mockMvc.perform(post("/api/auth/phone-login")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                    {"phoneNumber":"1390000abcd","verificationCode":"123456"}
                    """))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));
    }
}
