package com.aidrun.backend.order;

import com.aidrun.backend.order.dto.CancelOrderRequest;
import com.aidrun.backend.order.dto.CompleteOrderRequest;
import com.aidrun.backend.order.dto.CreateOrderRequest;
import com.aidrun.backend.order.dto.EmergencyRequest;
import com.aidrun.backend.order.dto.RatingDto;
import com.aidrun.backend.order.dto.RatingRequest;
import com.aidrun.backend.order.dto.RunOrderDto;
import com.aidrun.backend.user.AppUser;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/orders")
public class RunOrderController {

    private final RunOrderService runOrderService;

    public RunOrderController(RunOrderService runOrderService) {
        this.runOrderService = runOrderService;
    }

    @PostMapping
    public ResponseEntity<RunOrderDto> createOrder(
        @Valid @RequestBody CreateOrderRequest request,
        Authentication authentication
    ) {
        AppUser user = (AppUser) authentication.getPrincipal();
        RunOrderDto dto = runOrderService.createOrder(user, request);
        return ResponseEntity.status(HttpStatus.CREATED).body(dto);
    }

    @GetMapping("/my")
    public ResponseEntity<List<RunOrderDto>> getMyOrders(Authentication authentication) {
        AppUser user = (AppUser) authentication.getPrincipal();
        List<RunOrderDto> orders = runOrderService.getMyOrders(user);
        return ResponseEntity.ok(orders);
    }

    @GetMapping("/available")
    public ResponseEntity<List<RunOrderDto>> getAvailableOrders(Authentication authentication) {
        List<RunOrderDto> orders = runOrderService.getAvailableOrders();
        return ResponseEntity.ok(orders);
    }

    @GetMapping("/{orderId}")
    public ResponseEntity<RunOrderDto> getOrderDetail(
        @PathVariable String orderId,
        Authentication authentication
    ) {
        AppUser user = (AppUser) authentication.getPrincipal();
        RunOrderDto dto = runOrderService.getOrderDetail(user, orderId);
        return ResponseEntity.ok(dto);
    }

    @PostMapping("/{orderId}/accept")
    public ResponseEntity<RunOrderDto> acceptOrder(
        @PathVariable String orderId,
        Authentication authentication
    ) {
        AppUser user = (AppUser) authentication.getPrincipal();
        RunOrderDto dto = runOrderService.acceptOrder(user, orderId);
        return ResponseEntity.ok(dto);
    }

    @PostMapping("/{orderId}/arrive")
    public ResponseEntity<RunOrderDto> arrive(
        @PathVariable String orderId,
        Authentication authentication
    ) {
        AppUser user = (AppUser) authentication.getPrincipal();
        RunOrderDto dto = runOrderService.markArrived(user, orderId);
        return ResponseEntity.ok(dto);
    }

    @PostMapping("/{orderId}/confirm-start")
    public ResponseEntity<RunOrderDto> confirmStart(
        @PathVariable String orderId,
        Authentication authentication
    ) {
        AppUser user = (AppUser) authentication.getPrincipal();
        RunOrderDto dto = runOrderService.confirmStart(user, orderId);
        return ResponseEntity.ok(dto);
    }

    @PostMapping("/{orderId}/complete")
    public ResponseEntity<RunOrderDto> complete(
        @PathVariable String orderId,
        @RequestBody(required = false) CompleteOrderRequest request,
        Authentication authentication
    ) {
        AppUser user = (AppUser) authentication.getPrincipal();
        RunOrderDto dto = runOrderService.completeOrder(user, orderId, request);
        return ResponseEntity.ok(dto);
    }

    @PostMapping("/{orderId}/cancel")
    public ResponseEntity<RunOrderDto> cancel(
        @PathVariable String orderId,
        @Valid @RequestBody CancelOrderRequest request,
        Authentication authentication
    ) {
        AppUser user = (AppUser) authentication.getPrincipal();
        RunOrderDto dto = runOrderService.cancelOrder(user, orderId, request);
        return ResponseEntity.ok(dto);
    }

    @PostMapping("/{orderId}/emergency")
    public ResponseEntity<RunOrderDto> emergency(
        @PathVariable String orderId,
        @RequestBody(required = false) EmergencyRequest request,
        Authentication authentication
    ) {
        AppUser user = (AppUser) authentication.getPrincipal();
        RunOrderDto dto = runOrderService.triggerEmergency(user, orderId, request);
        return ResponseEntity.ok(dto);
    }

    @PostMapping("/{orderId}/rating")
    public ResponseEntity<RatingDto> submitRating(
        @PathVariable String orderId,
        @Valid @RequestBody RatingRequest request,
        Authentication authentication
    ) {
        AppUser user = (AppUser) authentication.getPrincipal();
        RatingDto dto = runOrderService.submitRating(user, orderId, request);
        return ResponseEntity.ok(dto);
    }
}
