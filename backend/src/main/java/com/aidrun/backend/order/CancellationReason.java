package com.aidrun.backend.order;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

public enum CancellationReason {
    TIME_CONFLICT("time_conflict"),
    WRONG_LOCATION("wrong_location"),
    TEMPORARY_ISSUE("temporary_issue"),
    CANNOT_CONTACT("cannot_contact"),
    OTHER("other");

    private final String wireValue;

    CancellationReason(String wireValue) {
        this.wireValue = wireValue;
    }

    @JsonValue
    public String getWireValue() {
        return wireValue;
    }

    @JsonCreator
    public static CancellationReason fromWireValue(String wireValue) {
        for (CancellationReason value : values()) {
            if (value.wireValue.equals(wireValue)) {
                return value;
            }
        }
        throw new IllegalArgumentException("Unsupported cancellation reason: " + wireValue);
    }
}
