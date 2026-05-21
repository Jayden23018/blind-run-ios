package com.aidrun.backend.common.error;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

public enum ErrorCode {
    INVALID_VERIFICATION_CODE("INVALID_VERIFICATION_CODE"),
    PROFILE_INCOMPLETE("PROFILE_INCOMPLETE"),
    LOCATION_PERMISSION_REQUIRED("LOCATION_PERMISSION_REQUIRED"),
    ORDER_NOT_FOUND("ORDER_NOT_FOUND"),
    ORDER_ALREADY_ACCEPTED("ORDER_ALREADY_ACCEPTED"),
    INVALID_ORDER_STATUS("INVALID_ORDER_STATUS"),
    ACTIVE_ORDER_ROLE_SWITCH_BLOCKED("ACTIVE_ORDER_ROLE_SWITCH_BLOCKED"),
    VOLUNTEER_NOT_AVAILABLE("VOLUNTEER_NOT_AVAILABLE"),
    VOLUNTEER_NOT_APPROVED("VOLUNTEER_NOT_APPROVED"),
    APPOINTMENT_TOO_SOON("APPOINTMENT_TOO_SOON"),
    VALIDATION_FAILED("VALIDATION_FAILED"),
    UNAUTHORIZED("UNAUTHORIZED");

    private final String wireValue;

    ErrorCode(String wireValue) {
        this.wireValue = wireValue;
    }

    @JsonValue
    public String getWireValue() {
        return wireValue;
    }

    @JsonCreator
    public static ErrorCode fromWireValue(String wireValue) {
        for (ErrorCode value : values()) {
            if (value.wireValue.equals(wireValue)) {
                return value;
            }
        }
        throw new IllegalArgumentException("Unsupported error code: " + wireValue);
    }
}
