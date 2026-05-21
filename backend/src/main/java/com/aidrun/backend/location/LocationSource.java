package com.aidrun.backend.location;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

public enum LocationSource {
    DEVICE_LOCATION("device_location"),
    MANUAL("manual"),
    DEMO_DEFAULT("demo_default");

    private final String wireValue;

    LocationSource(String wireValue) {
        this.wireValue = wireValue;
    }

    @JsonValue
    public String getWireValue() {
        return wireValue;
    }

    @JsonCreator
    public static LocationSource fromWireValue(String wireValue) {
        for (LocationSource value : values()) {
            if (value.wireValue.equals(wireValue)) {
                return value;
            }
        }
        throw new IllegalArgumentException("Unsupported location source: " + wireValue);
    }
}
