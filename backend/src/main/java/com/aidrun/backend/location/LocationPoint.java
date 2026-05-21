package com.aidrun.backend.location;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;

@Embeddable
public class LocationPoint {

    @Column(nullable = false)
    private Double latitude;

    @Column(nullable = false)
    private Double longitude;

    private String addressText;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private LocationSource source;

    protected LocationPoint() {
    }

    public LocationPoint(Double latitude, Double longitude, String addressText, LocationSource source) {
        this.latitude = latitude;
        this.longitude = longitude;
        this.addressText = addressText;
        this.source = source;
    }

    public Double getLatitude() {
        return latitude;
    }

    public Double getLongitude() {
        return longitude;
    }

    public String getAddressText() {
        return addressText;
    }

    public LocationSource getSource() {
        return source;
    }
}
