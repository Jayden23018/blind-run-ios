package com.aidrun.backend.order;

import com.aidrun.backend.common.BaseEntity;
import com.aidrun.backend.location.LocationPoint;
import com.aidrun.backend.user.AppUser;
import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Embedded;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToOne;
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

    @OneToOne(mappedBy = "order", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    private Cancellation cancellation;

    @OneToOne(mappedBy = "order", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    private EmergencyEvent emergencyEvent;

    @OneToOne(mappedBy = "order", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    private ServiceSummary serviceSummary;

    @OneToOne(mappedBy = "order", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    private OrderRating rating;

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

    // --- State transition methods ---

    public void assignVolunteer(AppUser volunteerUser, String volunteerNickname) {
        this.volunteerUser = volunteerUser;
        this.volunteerNickname = volunteerNickname;
        this.acceptedAt = Instant.now();
    }

    public void markAccepted(AppUser volunteerUser, String volunteerNickname) {
        this.status = RunOrderStatus.ACCEPTED;
        this.volunteerUser = volunteerUser;
        this.volunteerNickname = volunteerNickname;
        this.acceptedAt = Instant.now();
    }

    public void markArrived() {
        this.status = RunOrderStatus.ARRIVED;
        this.arrivedAt = Instant.now();
    }

    public void markStarted() {
        this.status = RunOrderStatus.IN_PROGRESS;
        this.startedAt = Instant.now();
    }

    public void markCompleted(Instant completedAt) {
        this.status = RunOrderStatus.COMPLETED;
        this.completedAt = completedAt;
    }

    public void markCancelled() {
        this.status = RunOrderStatus.CANCELLED;
        this.cancelledAt = Instant.now();
    }

    public void markEmergency() {
        this.status = RunOrderStatus.EMERGENCY;
        this.emergencyAt = Instant.now();
    }

    // --- Getters ---

    public RunOrderStatus getStatus() {
        return status;
    }

    public AppUser getBlindRunnerUser() {
        return blindRunnerUser;
    }

    public String getBlindRunnerNickname() {
        return blindRunnerNickname;
    }

    public AppUser getVolunteerUser() {
        return volunteerUser;
    }

    public String getVolunteerNickname() {
        return volunteerNickname;
    }

    public LocationPoint getStartLocation() {
        return startLocation;
    }

    public String getDestinationText() {
        return destinationText;
    }

    public Instant getAppointmentTime() {
        return appointmentTime;
    }

    public Integer getEstimatedDurationMinutes() {
        return estimatedDurationMinutes;
    }

    public BigDecimal getEstimatedDistanceKm() {
        return estimatedDistanceKm;
    }

    public String getPacePreference() {
        return pacePreference;
    }

    public Boolean getPreferSameGender() {
        return preferSameGender;
    }

    public String getRemark() {
        return remark;
    }

    public String getBlindRunnerPhone() {
        return blindRunnerPhone;
    }

    public Instant getAcceptedAt() {
        return acceptedAt;
    }

    public Instant getArrivedAt() {
        return arrivedAt;
    }

    public Instant getStartedAt() {
        return startedAt;
    }

    public Instant getCompletedAt() {
        return completedAt;
    }

    public Instant getCancelledAt() {
        return cancelledAt;
    }

    public Instant getEmergencyAt() {
        return emergencyAt;
    }

    public Cancellation getCancellation() {
        return cancellation;
    }

    public EmergencyEvent getEmergencyEvent() {
        return emergencyEvent;
    }

    public ServiceSummary getServiceSummary() {
        return serviceSummary;
    }

    public OrderRating getRating() {
        return rating;
    }

    // --- Setters for builder-style creation ---

    public void setEstimatedDurationMinutes(Integer estimatedDurationMinutes) {
        this.estimatedDurationMinutes = estimatedDurationMinutes;
    }

    public void setEstimatedDistanceKm(BigDecimal estimatedDistanceKm) {
        this.estimatedDistanceKm = estimatedDistanceKm;
    }

    public void setPacePreference(String pacePreference) {
        this.pacePreference = pacePreference;
    }

    public void setPreferSameGender(Boolean preferSameGender) {
        this.preferSameGender = preferSameGender;
    }

    public void setRemark(String remark) {
        this.remark = remark;
    }

    public void setBlindRunnerPhone(String blindRunnerPhone) {
        this.blindRunnerPhone = blindRunnerPhone;
    }

    public void setStatus(RunOrderStatus status) {
        this.status = status;
    }

    public void setEmergencyEvent(EmergencyEvent emergencyEvent) {
        this.emergencyEvent = emergencyEvent;
    }
}
