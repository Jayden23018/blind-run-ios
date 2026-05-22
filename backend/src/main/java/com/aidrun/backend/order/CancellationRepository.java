package com.aidrun.backend.order;

import org.springframework.data.jpa.repository.JpaRepository;

public interface CancellationRepository extends JpaRepository<Cancellation, String> {
}
