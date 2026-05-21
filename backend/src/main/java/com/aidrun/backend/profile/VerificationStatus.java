package com.aidrun.backend.profile;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

public enum VerificationStatus {
    NOT_SUBMITTED("not_submitted"),
    PENDING("pending"),
    APPROVED("approved"),
    REJECTED("rejected");

    private final String wireValue;

    VerificationStatus(String wireValue) {
        this.wireValue = wireValue;
    }

    @JsonValue
    public String getWireValue() {
        return wireValue;
    }

    @JsonCreator
    public static VerificationStatus fromWireValue(String wireValue) {
        for (VerificationStatus value : values()) {
            if (value.wireValue.equals(wireValue)) {
                return value;
            }
        }
        throw new IllegalArgumentException("Unsupported verification status: " + wireValue);
    }
}
