package com.aidrun.backend.order.dto;

import com.aidrun.backend.location.LocationPoint;
import com.aidrun.backend.location.LocationSource;
import jakarta.validation.constraints.NotNull;

public record LocationPointDto(
    @NotNull Double latitude,
    @NotNull Double longitude,
    String addressText,
    @NotNull LocationSource source
) {
    public static LocationPointDto from(LocationPoint entity) {
        if (entity == null) return null;
        return new LocationPointDto(
            entity.getLatitude(),
            entity.getLongitude(),
            entity.getAddressText(),
            entity.getSource()
        );
    }

    public LocationPoint toEntity() {
        return new LocationPoint(latitude, longitude, addressText, source);
    }
}
