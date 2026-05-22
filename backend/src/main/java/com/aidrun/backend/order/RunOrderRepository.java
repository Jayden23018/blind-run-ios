package com.aidrun.backend.order;

import com.aidrun.backend.user.AppUser;
import java.util.Collection;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
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

    List<RunOrder> findByStatus(RunOrderStatus status);

    @Query("SELECT o FROM RunOrder o WHERE o.blindRunnerUser = :user OR o.volunteerUser = :user ORDER BY o.createdAt DESC")
    List<RunOrder> findByUser(@Param("user") AppUser user);

    @Modifying
    @Query("UPDATE RunOrder o SET o.status = 'ACCEPTED', o.volunteerUser = :volunteer, " +
           "o.volunteerNickname = :nickname, o.acceptedAt = :now " +
           "WHERE o.id = :orderId AND o.status = 'MATCHING'")
    int acceptOrderAtomically(
        @Param("orderId") String orderId,
        @Param("volunteer") AppUser volunteer,
        @Param("nickname") String nickname,
        @Param("now") java.time.Instant now);
}
