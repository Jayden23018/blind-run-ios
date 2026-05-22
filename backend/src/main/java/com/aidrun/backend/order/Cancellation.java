package com.aidrun.backend.order;

import com.aidrun.backend.common.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "cancellations")
public class Cancellation extends BaseEntity {

    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "order_id", nullable = false, unique = true)
    private RunOrder order;

    @Enumerated(EnumType.STRING)
    private CancelledBy cancelledBy;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private CancellationReason cancelledReason;

    private String otherReasonText;

    protected Cancellation() {
    }

    public Cancellation(RunOrder order, CancelledBy cancelledBy, CancellationReason cancelledReason, String otherReasonText) {
        this.order = order;
        this.cancelledBy = cancelledBy;
        this.cancelledReason = cancelledReason;
        this.otherReasonText = otherReasonText;
    }

    public RunOrder getOrder() {
        return order;
    }

    public CancelledBy getCancelledBy() {
        return cancelledBy;
    }

    public CancellationReason getCancelledReason() {
        return cancelledReason;
    }

    public String getOtherReasonText() {
        return otherReasonText;
    }
}
