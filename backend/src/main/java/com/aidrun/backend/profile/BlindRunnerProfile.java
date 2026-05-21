package com.aidrun.backend.profile;

import com.aidrun.backend.common.BaseEntity;
import com.aidrun.backend.user.AppUser;
import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "blind_runner_profiles")
public class BlindRunnerProfile extends BaseEntity {

    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false, unique = true)
    private AppUser user;

    @Column(nullable = false)
    private String nickname;

    private String runningExperience;

    @OneToOne(mappedBy = "blindRunnerProfile", cascade = CascadeType.ALL, orphanRemoval = true, optional = false)
    private EmergencyContact emergencyContact;

    protected BlindRunnerProfile() {
    }

    public BlindRunnerProfile(AppUser user, String nickname, String runningExperience) {
        this.user = user;
        this.nickname = nickname;
        this.runningExperience = runningExperience;
    }

    public AppUser getUser() {
        return user;
    }

    public String getNickname() {
        return nickname;
    }

    public String getRunningExperience() {
        return runningExperience;
    }

    public EmergencyContact getEmergencyContact() {
        return emergencyContact;
    }

    public void setEmergencyContact(EmergencyContact emergencyContact) {
        this.emergencyContact = emergencyContact;
        emergencyContact.setBlindRunnerProfile(this);
    }
}
