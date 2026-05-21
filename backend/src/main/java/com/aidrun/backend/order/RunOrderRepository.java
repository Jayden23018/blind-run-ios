package com.aidrun.backend.order;

import java.util.Collection;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface RunOrderRepository extends JpaRepository<RunOrder, String> {

    long countByStatus(RunOrderStatus status);

    @Query("SELECT COUNT(o) > 0 FROM RunOrder o WHERE " +
           "(o.blindRunnerUser.id = :userId OR o.volunteerUser.id = :userId) " +
           "AND o.status IN :statuses")
    boolean existsByUserIdAndStatusIn(
        @Param("userId") String userId,
        @Param("statuses") Collection<RunOrderStatus> statuses);
}
