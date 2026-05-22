package com.aidrun.backend.profile;

import com.aidrun.backend.common.BaseEntity;
import com.aidrun.backend.user.AppUser;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "volunteer_profiles")
public class VolunteerProfile extends BaseEntity {

    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false, unique = true)
    private AppUser user;

    @Column(nullable = false)
    private String nickname;

    @Column(nullable = false)
    private String phoneNumber;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private VerificationStatus verificationStatus;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private AdminReviewStatus adminReviewStatus;

    @Column(nullable = false)
    private boolean available;

    @Column(nullable = false)
    private int pointsBalance;

    protected VolunteerProfile() {
    }

    public VolunteerProfile(
        AppUser user,
        String nickname,
        String phoneNumber,
        VerificationStatus verificationStatus,
        AdminReviewStatus adminReviewStatus,
        boolean available,
        int pointsBalance
    ) {
        this.user = user;
        this.nickname = nickname;
        this.phoneNumber = phoneNumber;
        this.verificationStatus = verificationStatus;
        this.adminReviewStatus = adminReviewStatus;
        this.available = available;
        this.pointsBalance = pointsBalance;
    }

    public AppUser getUser() {
        return user;
    }

    public String getNickname() {
        return nickname;
    }

    public String getPhoneNumber() {
        return phoneNumber;
    }

    public boolean isAvailable() {
        return available;
    }

    public VerificationStatus getVerificationStatus() {
        return verificationStatus;
    }

    public AdminReviewStatus getAdminReviewStatus() {
        return adminReviewStatus;
    }

    public int getPointsBalance() {
        return pointsBalance;
    }

    public void setNickname(String nickname) {
        this.nickname = nickname;
    }

    public void setVerificationStatus(VerificationStatus verificationStatus) {
        this.verificationStatus = verificationStatus;
    }

    public void setAdminReviewStatus(AdminReviewStatus adminReviewStatus) {
        this.adminReviewStatus = adminReviewStatus;
    }

    public void setAvailable(boolean available) {
        this.available = available;
    }
}
