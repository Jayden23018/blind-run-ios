package com.aidrun.backend.order;

import com.aidrun.backend.common.BaseEntity;
import com.aidrun.backend.user.UserRole;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "emergency_events")
public class EmergencyEvent extends BaseEntity {

    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "order_id", nullable = false, unique = true)
    private RunOrder order;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private UserRole triggeredByRole;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private RunOrderStatus previousStatus;

    private String note;

    protected EmergencyEvent() {
    }

    public EmergencyEvent(RunOrder order, UserRole triggeredByRole, RunOrderStatus previousStatus, String note) {
        this.order = order;
        this.triggeredByRole = triggeredByRole;
        this.previousStatus = previousStatus;
        this.note = note;
    }

    public RunOrder getOrder() {
        return order;
    }

    public UserRole getTriggeredByRole() {
        return triggeredByRole;
    }

    public RunOrderStatus getPreviousStatus() {
        return previousStatus;
    }

    public String getNote() {
        return note;
    }
}
