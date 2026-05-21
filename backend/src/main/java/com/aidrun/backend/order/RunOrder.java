package com.aidrun.backend.order;

import com.aidrun.backend.common.BaseEntity;
import com.aidrun.backend.location.LocationPoint;
import com.aidrun.backend.user.AppUser;
import jakarta.persistence.Column;
import jakarta.persistence.Embedded;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.Instant;

@Entity
@Table(name = "run_orders")
public class RunOrder extends BaseEntity {

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "blind_runner_user_id", nullable = false)
    private AppUser blindRunnerUser;

    @Column(nullable = false)
    private String blindRunnerNickname;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "volunteer_user_id")
    private AppUser volunteerUser;

    private String volunteerNickname;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private RunOrderStatus status;

    @Embedded
    private LocationPoint startLocation;

    private String destinationText;

    @Column(nullable = false)
    private Instant appointmentTime;

    private Integer estimatedDurationMinutes;
    private BigDecimal estimatedDistanceKm;
    private String pacePreference;
    private Boolean preferSameGender;
    private String remark;
    private String blindRunnerPhone;
    private Instant acceptedAt;
    private Instant arrivedAt;
    private Instant startedAt;
    private Instant completedAt;
    private Instant cancelledAt;
    private Instant emergencyAt;

    protected RunOrder() {
    }

    public RunOrder(
        AppUser blindRunnerUser,
        String blindRunnerNickname,
        RunOrderStatus status,
        LocationPoint startLocation,
        String destinationText,
        Instant appointmentTime
    ) {
        this.blindRunnerUser = blindRunnerUser;
        this.blindRunnerNickname = blindRunnerNickname;
        this.status = status;
        this.startLocation = startLocation;
        this.destinationText = destinationText;
        this.appointmentTime = appointmentTime;
    }

    public void assignVolunteer(AppUser volunteerUser, String volunteerNickname) {
        this.volunteerUser = volunteerUser;
        this.volunteerNickname = volunteerNickname;
        this.acceptedAt = Instant.now();
    }

    public void markCompleted(Instant completedAt) {
        this.status = RunOrderStatus.COMPLETED;
        this.completedAt = completedAt;
    }

    public RunOrderStatus getStatus() {
        return status;
    }

    public AppUser getBlindRunnerUser() {
        return blindRunnerUser;
    }

    public AppUser getVolunteerUser() {
        return volunteerUser;
    }
}
