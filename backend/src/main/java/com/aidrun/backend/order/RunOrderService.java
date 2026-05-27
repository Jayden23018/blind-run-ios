package com.aidrun.backend.order;

import com.aidrun.backend.common.error.ApiException;
import com.aidrun.backend.common.error.ErrorCode;
import com.aidrun.backend.order.dto.CancelOrderRequest;
import com.aidrun.backend.order.dto.CompleteOrderRequest;
import com.aidrun.backend.order.dto.CreateOrderRequest;
import com.aidrun.backend.order.dto.EmergencyRequest;
import com.aidrun.backend.order.dto.RatingDto;
import com.aidrun.backend.order.dto.RatingRequest;
import com.aidrun.backend.order.dto.RunOrderDto;
import com.aidrun.backend.profile.BlindRunnerProfile;
import com.aidrun.backend.profile.BlindRunnerProfileRepository;
import com.aidrun.backend.profile.VolunteerProfile;
import com.aidrun.backend.profile.VolunteerProfileRepository;
import com.aidrun.backend.user.AppUser;
import com.aidrun.backend.user.UserRole;
import com.aidrun.backend.volunteer.VolunteerPointsLedger;
import com.aidrun.backend.volunteer.VolunteerPointsLedgerRepository;
import com.aidrun.backend.volunteer.VolunteerService;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Set;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class RunOrderService {

    private static final int POINTS_PER_COMPLETION = 100;
    private static final long MIN_APPOINTMENT_MINUTES_AHEAD = 30;
    private static final Set<RunOrderStatus> CANCELLABLE_STATUSES = Set.of(
        RunOrderStatus.MATCHING, RunOrderStatus.ACCEPTED, RunOrderStatus.ARRIVED
    );
    private static final Set<RunOrderStatus> EMERGENCY_ALLOWED_STATUSES = Set.of(
        RunOrderStatus.ACCEPTED, RunOrderStatus.ARRIVED, RunOrderStatus.IN_PROGRESS
    );

    private final RunOrderRepository runOrderRepository;
    private final CancellationRepository cancellationRepository;
    private final EmergencyEventRepository emergencyEventRepository;
    private final ServiceSummaryRepository serviceSummaryRepository;
    private final OrderRatingRepository orderRatingRepository;
    private final BlindRunnerProfileRepository blindRunnerProfileRepository;
    private final VolunteerProfileRepository volunteerProfileRepository;
    private final VolunteerPointsLedgerRepository pointsLedgerRepository;
    private final VolunteerService volunteerService;

    public RunOrderService(
        RunOrderRepository runOrderRepository,
        CancellationRepository cancellationRepository,
        EmergencyEventRepository emergencyEventRepository,
        ServiceSummaryRepository serviceSummaryRepository,
        OrderRatingRepository orderRatingRepository,
        BlindRunnerProfileRepository blindRunnerProfileRepository,
        VolunteerProfileRepository volunteerProfileRepository,
        VolunteerPointsLedgerRepository pointsLedgerRepository,
        VolunteerService volunteerService
    ) {
        this.runOrderRepository = runOrderRepository;
        this.cancellationRepository = cancellationRepository;
        this.emergencyEventRepository = emergencyEventRepository;
        this.serviceSummaryRepository = serviceSummaryRepository;
        this.orderRatingRepository = orderRatingRepository;
        this.blindRunnerProfileRepository = blindRunnerProfileRepository;
        this.volunteerProfileRepository = volunteerProfileRepository;
        this.pointsLedgerRepository = pointsLedgerRepository;
        this.volunteerService = volunteerService;
    }

    @Transactional
    public RunOrderDto createOrder(AppUser user, CreateOrderRequest request) {
        BlindRunnerProfile profile = blindRunnerProfileRepository.findByUser(user)
            .orElseThrow(() -> new ApiException(
                ErrorCode.PROFILE_INCOMPLETE,
                "请先完善盲人跑者资料和紧急联系人",
                HttpStatus.BAD_REQUEST
            ));

        if (profile.getEmergencyContact() == null) {
            throw new ApiException(
                ErrorCode.PROFILE_INCOMPLETE,
                "请先完善盲人跑者资料和紧急联系人",
                HttpStatus.BAD_REQUEST
            );
        }

        if (request.startLocation() == null
            || request.startLocation().latitude() == null
            || request.startLocation().longitude() == null) {
            throw new ApiException(
                ErrorCode.LOCATION_PERMISSION_REQUIRED,
                "创建预约需要提供位置坐标",
                HttpStatus.BAD_REQUEST
            );
        }

        Instant minAppointmentTime = Instant.now().plus(MIN_APPOINTMENT_MINUTES_AHEAD, ChronoUnit.MINUTES);
        if (request.appointmentTime().isBefore(minAppointmentTime)) {
            throw new ApiException(
                ErrorCode.APPOINTMENT_TOO_SOON,
                "预约时间至少需要在 30 分钟后",
                HttpStatus.BAD_REQUEST
            );
        }

        RunOrder order = new RunOrder(
            user,
            profile.getNickname(),
            RunOrderStatus.MATCHING,
            request.startLocation().toEntity(),
            request.destinationText(),
            request.appointmentTime()
        );
        order.setBlindRunnerPhone(user.getPhoneNumber());
        order.setEstimatedDurationMinutes(request.estimatedDurationMinutes());
        order.setEstimatedDistanceKm(request.estimatedDistanceKm());
        order.setPacePreference(request.pacePreference());
        order.setPreferSameGender(request.preferSameGender());
        order.setRemark(request.remark());

        RunOrder saved = runOrderRepository.save(order);
        return RunOrderDto.from(saved, true);
    }

    @Transactional(readOnly = true)
    public List<RunOrderDto> getMyOrders(AppUser user) {
        List<RunOrder> orders = runOrderRepository.findByUser(user);
        return orders.stream()
            .map(o -> RunOrderDto.from(o, shouldShowPhone(o, user)))
            .toList();
    }

    @Transactional(readOnly = true)
    public List<RunOrderDto> getAvailableOrders() {
        List<RunOrder> orders = runOrderRepository.findByStatus(RunOrderStatus.MATCHING);
        return orders.stream()
            .map(o -> RunOrderDto.from(o, false))
            .toList();
    }

    @Transactional(readOnly = true)
    public RunOrderDto getOrderDetail(AppUser user, String orderId) {
        RunOrder order = findOrderOrThrow(orderId);
        return RunOrderDto.from(order, shouldShowPhone(order, user));
    }

    @Transactional
    public RunOrderDto acceptOrder(AppUser volunteer, String orderId) {
        volunteerService.validateVolunteerCanAcceptOrder(volunteer);

        VolunteerProfile volProfile = volunteerProfileRepository.findByUser(volunteer)
            .orElseThrow(() -> new ApiException(
                ErrorCode.PROFILE_INCOMPLETE,
                "请先完善志愿者资料",
                HttpStatus.BAD_REQUEST
            ));

        int updated = runOrderRepository.acceptOrderAtomically(
            orderId, volunteer, volProfile.getNickname(), Instant.now()
        );

        if (updated == 0) {
            if (!runOrderRepository.existsById(orderId)) {
                throw new ApiException(
                    ErrorCode.ORDER_NOT_FOUND,
                    "订单不存在",
                    HttpStatus.NOT_FOUND
                );
            }
            throw new ApiException(
                ErrorCode.ORDER_ALREADY_ACCEPTED,
                "订单已被其他志愿者接单",
                HttpStatus.CONFLICT
            );
        }

        RunOrder order = findOrderOrThrow(orderId);
        return RunOrderDto.from(order, true);
    }

    @Transactional
    public RunOrderDto markArrived(AppUser volunteer, String orderId) {
        RunOrder order = findOrderOrThrow(orderId);

        if (order.getStatus() != RunOrderStatus.ACCEPTED) {
            throw new ApiException(
                ErrorCode.INVALID_ORDER_STATUS,
                "当前订单状态不允许该操作",
                HttpStatus.CONFLICT
            );
        }
        validateIsAssignedVolunteer(order, volunteer);

        order.markArrived();
        RunOrder saved = runOrderRepository.save(order);
        return RunOrderDto.from(saved, true);
    }

    @Transactional
    public RunOrderDto confirmStart(AppUser blindRunner, String orderId) {
        RunOrder order = findOrderOrThrow(orderId);

        if (order.getStatus() != RunOrderStatus.ARRIVED) {
            throw new ApiException(
                ErrorCode.INVALID_ORDER_STATUS,
                "当前订单状态不允许该操作",
                HttpStatus.CONFLICT
            );
        }
        validateIsBlindRunner(order, blindRunner);

        order.markStarted();
        RunOrder saved = runOrderRepository.save(order);
        return RunOrderDto.from(saved, true);
    }

    @Transactional
    public RunOrderDto completeOrder(AppUser volunteer, String orderId, CompleteOrderRequest request) {
        RunOrder order = findOrderOrThrow(orderId);

        if (order.getStatus() != RunOrderStatus.IN_PROGRESS) {
            throw new ApiException(
                ErrorCode.INVALID_ORDER_STATUS,
                "当前订单状态不允许该操作",
                HttpStatus.CONFLICT
            );
        }
        validateIsAssignedVolunteer(order, volunteer);

        order.markCompleted(Instant.now());

        if (request != null && request.summaryText() != null && !request.summaryText().isBlank()) {
            ServiceSummary summary = new ServiceSummary(order, volunteer, request.summaryText());
            serviceSummaryRepository.save(summary);
        }

        // Award points
        VolunteerProfile volProfile = volunteerProfileRepository.findByUser(volunteer)
            .orElseThrow(() -> new ApiException(
                ErrorCode.PROFILE_INCOMPLETE,
                "志愿者资料不存在",
                HttpStatus.BAD_REQUEST
            ));
        volProfile.addPoints(POINTS_PER_COMPLETION);
        volunteerProfileRepository.save(volProfile);
        pointsLedgerRepository.save(
            new VolunteerPointsLedger(volunteer, order, POINTS_PER_COMPLETION, "service_completed")
        );

        RunOrder saved = runOrderRepository.save(order);
        return RunOrderDto.from(saved, true);
    }

    @Transactional
    public RunOrderDto cancelOrder(AppUser user, String orderId, CancelOrderRequest request) {
        RunOrder order = findOrderOrThrow(orderId);

        if (!CANCELLABLE_STATUSES.contains(order.getStatus())) {
            throw new ApiException(
                ErrorCode.INVALID_ORDER_STATUS,
                "当前订单状态不允许取消",
                HttpStatus.CONFLICT
            );
        }
        validateIsParticipant(order, user);

        CancelledBy cancelledBy = mapRoleToCancelledBy(determineRoleInOrder(order, user));

        order.markCancelled();
        Cancellation cancellation = new Cancellation(
            order, cancelledBy, request.cancelledReason(), request.otherReasonText()
        );
        cancellationRepository.save(cancellation);

        RunOrder saved = runOrderRepository.save(order);
        return RunOrderDto.from(saved, shouldShowPhone(saved, user));
    }

    @Transactional
    public RunOrderDto triggerEmergency(AppUser user, String orderId, EmergencyRequest request) {
        RunOrder order = findOrderOrThrow(orderId);

        if (!EMERGENCY_ALLOWED_STATUSES.contains(order.getStatus())) {
            throw new ApiException(
                ErrorCode.INVALID_ORDER_STATUS,
                "当前订单状态不允许该操作",
                HttpStatus.CONFLICT
            );
        }
        validateIsParticipant(order, user);

        RunOrderStatus previousStatus = order.getStatus();
        UserRole triggeredByRole = determineRoleInOrder(order, user);

        order.markEmergency();
        EmergencyEvent event = new EmergencyEvent(order, triggeredByRole, previousStatus,
            request != null ? request.note() : null);
        emergencyEventRepository.save(event);
        order.setEmergencyEvent(event);

        RunOrder saved = runOrderRepository.save(order);
        return RunOrderDto.from(saved, shouldShowPhone(saved, user));
    }

    @Transactional
    public RatingDto submitRating(AppUser blindRunner, String orderId, RatingRequest request) {
        RunOrder order = findOrderOrThrow(orderId);

        if (order.getStatus() != RunOrderStatus.COMPLETED) {
            throw new ApiException(
                ErrorCode.INVALID_ORDER_STATUS,
                "只有已完成的订单才能评分",
                HttpStatus.CONFLICT
            );
        }
        validateIsBlindRunner(order, blindRunner);

        if (order.getRating() != null) {
            throw new ApiException(
                ErrorCode.INVALID_ORDER_STATUS,
                "该订单已评分",
                HttpStatus.CONFLICT
            );
        }

        OrderRating rating = new OrderRating(
            order, blindRunner, order.getVolunteerUser(), request.stars(), request.comment()
        );
        OrderRating saved = orderRatingRepository.save(rating);
        return RatingDto.from(saved);
    }

    // --- Private helpers ---

    private RunOrder findOrderOrThrow(String orderId) {
        return runOrderRepository.findById(orderId)
            .orElseThrow(() -> new ApiException(
                ErrorCode.ORDER_NOT_FOUND,
                "订单不存在",
                HttpStatus.NOT_FOUND
            ));
    }

    private boolean shouldShowPhone(RunOrder order, AppUser currentUser) {
        if (order.getBlindRunnerUser().getId().equals(currentUser.getId())) {
            return true;
        }
        if (order.getVolunteerUser() != null
            && order.getVolunteerUser().getId().equals(currentUser.getId())
            && order.getStatus() != RunOrderStatus.MATCHING) {
            return true;
        }
        return false;
    }

    private void validateIsAssignedVolunteer(RunOrder order, AppUser user) {
        if (order.getVolunteerUser() == null || !order.getVolunteerUser().getId().equals(user.getId())) {
            throw new ApiException(
                ErrorCode.INVALID_ORDER_STATUS,
                "您不是该订单的志愿者",
                HttpStatus.FORBIDDEN
            );
        }
    }

    private void validateIsBlindRunner(RunOrder order, AppUser user) {
        if (!order.getBlindRunnerUser().getId().equals(user.getId())) {
            throw new ApiException(
                ErrorCode.INVALID_ORDER_STATUS,
                "您不是该订单的盲人跑者",
                HttpStatus.FORBIDDEN
            );
        }
    }

    private void validateIsParticipant(RunOrder order, AppUser user) {
        boolean isBlindRunner = order.getBlindRunnerUser().getId().equals(user.getId());
        boolean isVolunteer = order.getVolunteerUser() != null
            && order.getVolunteerUser().getId().equals(user.getId());
        if (!isBlindRunner && !isVolunteer) {
            throw new ApiException(
                ErrorCode.INVALID_ORDER_STATUS,
                "您不是该订单的参与者",
                HttpStatus.FORBIDDEN
            );
        }
    }

    private UserRole determineRoleInOrder(RunOrder order, AppUser user) {
        if (order.getBlindRunnerUser().getId().equals(user.getId())) {
            return UserRole.BLIND_RUNNER;
        }
        return UserRole.VOLUNTEER;
    }

    private CancelledBy mapRoleToCancelledBy(UserRole role) {
        return role == UserRole.BLIND_RUNNER ? CancelledBy.BLIND_RUNNER : CancelledBy.VOLUNTEER;
    }
}
