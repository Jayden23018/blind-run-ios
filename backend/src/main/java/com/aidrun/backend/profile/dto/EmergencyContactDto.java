package com.aidrun.backend.profile.dto;

import com.aidrun.backend.profile.EmergencyContact;

public record EmergencyContactDto(
    String name,
    String phoneNumber
) {

    public static EmergencyContactDto from(EmergencyContact contact) {
        if (contact == null) {
            return null;
        }
        return new EmergencyContactDto(contact.getName(), contact.getPhoneNumber());
    }
}
