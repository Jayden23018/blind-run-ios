package com.aidrun.backend.volunteer;

import com.aidrun.backend.common.BaseEntity;
import com.aidrun.backend.order.RunOrder;
import com.aidrun.backend.user.AppUser;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "volunteer_points_ledger")
public class VolunteerPointsLedger extends BaseEntity {

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "volunteer_user_id", nullable = false)
    private AppUser volunteerUser;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "order_id")
    private RunOrder order;

    @Column(nullable = false)
    private int pointsDelta;

    @Column(nullable = false)
    private String reason;

    protected VolunteerPointsLedger() {
    }

    public VolunteerPointsLedger(AppUser volunteerUser, RunOrder order, int pointsDelta, String reason) {
        this.volunteerUser = volunteerUser;
        this.order = order;
        this.pointsDelta = pointsDelta;
        this.reason = reason;
    }

    public int getPointsDelta() {
        return pointsDelta;
    }

    public String getReason() {
        return reason;
    }
}
