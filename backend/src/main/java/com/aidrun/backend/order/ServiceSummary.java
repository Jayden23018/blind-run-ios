package com.aidrun.backend.order;

import com.aidrun.backend.common.BaseEntity;
import com.aidrun.backend.user.AppUser;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "service_summaries")
public class ServiceSummary extends BaseEntity {

    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "order_id", nullable = false, unique = true)
    private RunOrder order;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "volunteer_user_id", nullable = false)
    private AppUser volunteerUser;

    private String summaryText;

    protected ServiceSummary() {
    }

    public ServiceSummary(RunOrder order, AppUser volunteerUser, String summaryText) {
        this.order = order;
        this.volunteerUser = volunteerUser;
        this.summaryText = summaryText;
    }

    public RunOrder getOrder() {
        return order;
    }

    public AppUser getVolunteerUser() {
        return volunteerUser;
    }

    public String getSummaryText() {
        return summaryText;
    }
}
