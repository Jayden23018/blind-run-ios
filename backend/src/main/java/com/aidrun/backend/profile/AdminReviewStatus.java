package com.aidrun.backend.profile;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

public enum AdminReviewStatus {
    NOT_SUBMITTED("not_submitted"),
    PENDING("pending"),
    APPROVED("approved"),
    REJECTED("rejected");

    private final String wireValue;

    AdminReviewStatus(String wireValue) {
        this.wireValue = wireValue;
    }

    @JsonValue
    public String getWireValue() {
        return wireValue;
    }

    @JsonCreator
    public static AdminReviewStatus fromWireValue(String wireValue) {
        for (AdminReviewStatus value : values()) {
            if (value.wireValue.equals(wireValue)) {
                return value;
            }
        }
        throw new IllegalArgumentException("Unsupported admin review status: " + wireValue);
    }
}
