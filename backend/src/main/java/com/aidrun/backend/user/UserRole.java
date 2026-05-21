package com.aidrun.backend.user;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

public enum UserRole {
    BLIND_RUNNER("blind_runner"),
    VOLUNTEER("volunteer");

    private final String wireValue;

    UserRole(String wireValue) {
        this.wireValue = wireValue;
    }

    @JsonValue
    public String getWireValue() {
        return wireValue;
    }

    @JsonCreator
    public static UserRole fromWireValue(String wireValue) {
        for (UserRole value : values()) {
            if (value.wireValue.equals(wireValue)) {
                return value;
            }
        }
        throw new IllegalArgumentException("Unsupported user role: " + wireValue);
    }
}
