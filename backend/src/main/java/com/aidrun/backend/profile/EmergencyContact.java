package com.aidrun.backend.profile;

import com.aidrun.backend.common.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "emergency_contacts")
public class EmergencyContact extends BaseEntity {

    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "blind_runner_profile_id", nullable = false, unique = true)
    private BlindRunnerProfile blindRunnerProfile;

    @Column(nullable = false)
    private String name;

    @Column(nullable = false)
    private String phoneNumber;

    protected EmergencyContact() {
    }

    public EmergencyContact(String name, String phoneNumber) {
        this.name = name;
        this.phoneNumber = phoneNumber;
    }

    void setBlindRunnerProfile(BlindRunnerProfile blindRunnerProfile) {
        this.blindRunnerProfile = blindRunnerProfile;
    }

    public String getName() {
        return name;
    }

    public String getPhoneNumber() {
        return phoneNumber;
    }
}
