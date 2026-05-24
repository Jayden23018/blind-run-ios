package com.aidrun.backend.order;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

public enum RunOrderStatus {
    MATCHING("matching"),
    ACCEPTED("accepted"),
    ARRIVED("arrived"),
    IN_PROGRESS("in_progress"),
    COMPLETED("completed"),
    CANCELLED("cancelled"),
    EMERGENCY("emergency");

    private final String wireValue;

    RunOrderStatus(String wireValue) {
        this.wireValue = wireValue;
    }

    @JsonValue
    public String getWireValue() {
        return wireValue;
    }

    @JsonCreator
    public static RunOrderStatus fromWireValue(String wireValue) {
        for (RunOrderStatus value : values()) {
            if (value.wireValue.equals(wireValue)) {
                return value;
            }
        }
        throw new IllegalArgumentException("Unsupported run order status: " + wireValue);
    }
}
