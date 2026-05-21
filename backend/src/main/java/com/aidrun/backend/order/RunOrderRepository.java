package com.aidrun.backend.order;

import org.springframework.data.jpa.repository.JpaRepository;

public interface RunOrderRepository extends JpaRepository<RunOrder, String> {

    long countByStatus(RunOrderStatus status);
}
