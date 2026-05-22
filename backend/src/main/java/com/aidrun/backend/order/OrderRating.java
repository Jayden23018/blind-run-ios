package com.aidrun.backend.order;

import com.aidrun.backend.common.BaseEntity;
import com.aidrun.backend.user.AppUser;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "order_ratings")
public class OrderRating extends BaseEntity {

    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "order_id", nullable = false, unique = true)
    private RunOrder order;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "blind_runner_user_id", nullable = false)
    private AppUser blindRunnerUser;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "volunteer_user_id", nullable = false)
    private AppUser volunteerUser;

    @Column(nullable = false)
    private int stars;

    private String comment;

    protected OrderRating() {
    }

    public OrderRating(RunOrder order, AppUser blindRunnerUser, AppUser volunteerUser, int stars, String comment) {
        this.order = order;
        this.blindRunnerUser = blindRunnerUser;
        this.volunteerUser = volunteerUser;
        this.stars = stars;
        this.comment = comment;
    }

    public RunOrder getOrder() {
        return order;
    }

    public AppUser getBlindRunnerUser() {
        return blindRunnerUser;
    }

    public AppUser getVolunteerUser() {
        return volunteerUser;
    }

    public int getStars() {
        return stars;
    }

    public String getComment() {
        return comment;
    }
}
