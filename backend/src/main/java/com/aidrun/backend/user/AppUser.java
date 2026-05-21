package com.aidrun.backend.user;

import com.aidrun.backend.common.BaseEntity;
import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Table;
import java.util.LinkedHashSet;
import java.util.Set;

@Entity
@Table(name = "users")
public class AppUser extends BaseEntity {

    @Column(nullable = false, unique = true)
    private String phoneNumber;

    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(name = "user_roles", joinColumns = @JoinColumn(name = "user_id"))
    @Enumerated(EnumType.STRING)
    @Column(name = "role", nullable = false)
    private Set<UserRole> roles = new LinkedHashSet<>();

    @Enumerated(EnumType.STRING)
    private UserRole activeRole;

    protected AppUser() {
    }

    public AppUser(String phoneNumber, Set<UserRole> roles, UserRole activeRole) {
        this.phoneNumber = phoneNumber;
        this.roles = new LinkedHashSet<>(roles);
        this.activeRole = activeRole;
    }

    public String getPhoneNumber() {
        return phoneNumber;
    }

    public Set<UserRole> getRoles() {
        return roles;
    }

    public UserRole getActiveRole() {
        return activeRole;
    }

    public void setActiveRole(UserRole activeRole) {
        this.activeRole = activeRole;
    }
}
