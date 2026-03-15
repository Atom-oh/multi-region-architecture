package com.mall.order.service;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.mall.common.saga.SagaOrchestrator;
import com.mall.common.saga.SagaOrchestrator.SagaStep;
import com.mall.order.dto.CreateOrderRequest;
import com.mall.order.dto.OrderResponse;
import com.mall.order.event.OrderEventPublisher;
import com.mall.order.model.Order;
import com.mall.order.model.OrderItem;
import com.mall.order.model.OrderStatus;
import com.mall.order.repository.OrderRepository;

@Service
public class OrderService {

    private static final Logger log = LoggerFactory.getLogger(OrderService.class);

    private final OrderRepository orderRepository;
    private final OrderEventPublisher eventPublisher;

    public OrderService(OrderRepository orderRepository, OrderEventPublisher eventPublisher) {
        this.orderRepository = orderRepository;
        this.eventPublisher = eventPublisher;
    }

    @Transactional
    public OrderResponse createOrder(CreateOrderRequest request) throws SagaOrchestrator.SagaException {
        Order order = new Order();
        order.setUserId(request.userId());
        order.setStatus(OrderStatus.PENDING);

        BigDecimal total = BigDecimal.ZERO;
        for (CreateOrderRequest.OrderItemRequest itemReq : request.items()) {
            OrderItem item = new OrderItem();
            item.setProductId(itemReq.productId());
            item.setSku(itemReq.sku());
            item.setQuantity(itemReq.quantity());
            item.setPrice(itemReq.price());
            order.addItem(item);
            total = total.add(itemReq.price().multiply(BigDecimal.valueOf(itemReq.quantity())));
        }
        order.setTotalAmount(total);

        Order savedOrder = orderRepository.save(order);
        log.info("Created order: {}", savedOrder.getId());

        // Execute saga for order processing
        SagaOrchestrator saga = new SagaOrchestrator("CreateOrder")
                .addStep(new ReserveInventoryStep(savedOrder))
                .addStep(new ProcessPaymentStep(savedOrder))
                .addStep(new ConfirmOrderStep(savedOrder, orderRepository));

        saga.execute();

        Order confirmedOrder = orderRepository.findById(savedOrder.getId()).orElseThrow();
        OrderResponse response = OrderResponse.from(confirmedOrder);
        eventPublisher.publishOrderConfirmed(response);

        return response;
    }

    @Transactional(readOnly = true)
    public OrderResponse getOrder(UUID orderId) {
        Order order = orderRepository.findById(orderId)
                .orElseThrow(() -> new OrderNotFoundException(orderId));
        return OrderResponse.from(order);
    }

    @Transactional(readOnly = true)
    public List<OrderResponse> getOrdersByUser(String userId) {
        return orderRepository.findByUserIdOrderByCreatedAtDesc(userId)
                .stream()
                .map(OrderResponse::from)
                .toList();
    }

    @Transactional
    public OrderResponse cancelOrder(UUID orderId) {
        Order order = orderRepository.findById(orderId)
                .orElseThrow(() -> new OrderNotFoundException(orderId));

        if (order.getStatus() == OrderStatus.CANCELLED) {
            return OrderResponse.from(order);
        }

        if (order.getStatus() != OrderStatus.PENDING && order.getStatus() != OrderStatus.CONFIRMED) {
            throw new IllegalStateException("Cannot cancel order in status: " + order.getStatus());
        }

        order.setStatus(OrderStatus.CANCELLED);
        Order savedOrder = orderRepository.save(order);

        OrderResponse response = OrderResponse.from(savedOrder);
        eventPublisher.publishOrderCancelled(response);

        log.info("Cancelled order: {}", orderId);
        return response;
    }

    // Saga Steps

    private static class ReserveInventoryStep implements SagaStep {
        private final Order order;

        ReserveInventoryStep(Order order) {
            this.order = order;
        }

        @Override
        public String name() {
            return "ReserveInventory";
        }

        @Override
        public void execute() {
            // In a real system, call inventory service to reserve items
            log.info("Reserving inventory for order: {}", order.getId());
        }

        @Override
        public void compensate() {
            // Release reserved inventory
            log.info("Releasing inventory for order: {}", order.getId());
        }
    }

    private static class ProcessPaymentStep implements SagaStep {
        private final Order order;

        ProcessPaymentStep(Order order) {
            this.order = order;
        }

        @Override
        public String name() {
            return "ProcessPayment";
        }

        @Override
        public void execute() {
            // In a real system, call payment service
            log.info("Processing payment for order: {}", order.getId());
        }

        @Override
        public void compensate() {
            // Refund payment
            log.info("Refunding payment for order: {}", order.getId());
        }
    }

    private static class ConfirmOrderStep implements SagaStep {
        private final Order order;
        private final OrderRepository repository;

        ConfirmOrderStep(Order order, OrderRepository repository) {
            this.order = order;
            this.repository = repository;
        }

        @Override
        public String name() {
            return "ConfirmOrder";
        }

        @Override
        public void execute() {
            order.setStatus(OrderStatus.CONFIRMED);
            repository.save(order);
            log.info("Confirmed order: {}", order.getId());
        }

        @Override
        public void compensate() {
            order.setStatus(OrderStatus.FAILED);
            repository.save(order);
            log.info("Marked order as failed: {}", order.getId());
        }
    }

    public static class OrderNotFoundException extends RuntimeException {
        public OrderNotFoundException(UUID orderId) {
            super("Order not found: " + orderId);
        }
    }
}
