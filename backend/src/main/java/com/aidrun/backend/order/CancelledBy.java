package com.aidrun.backend.order;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

/**
 * Matches the OpenAPI CancellationActor schema while keeping the AGENTS.md requested type name.
 */
public enum CancelledBy {
    BLIND_RUNNER("blind_runner"),
    VOLUNTEER("volunteer");

    private final String wireValue;

    CancelledBy(String wireValue) {
        this.wireValue = wireValue;
    }

    @JsonValue
    public String getWireValue() {
        return wireValue;
    }

    @JsonCreator
    public static CancelledBy fromWireValue(String wireValue) {
        for (CancelledBy value : values()) {
            if (value.wireValue.equals(wireValue)) {
                return value;
            }
        }
        throw new IllegalArgumentException("Unsupported cancellation actor: " + wireValue);
    }
}
