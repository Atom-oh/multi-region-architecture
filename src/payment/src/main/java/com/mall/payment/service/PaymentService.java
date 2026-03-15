package com.mall.payment.service;

import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.mall.payment.dto.CreatePaymentRequest;
import com.mall.payment.dto.PaymentResponse;
import com.mall.payment.event.PaymentEventPublisher;
import com.mall.payment.model.Payment;
import com.mall.payment.model.PaymentStatus;
import com.mall.payment.repository.PaymentRepository;

@Service
public class PaymentService {

    private static final Logger log = LoggerFactory.getLogger(PaymentService.class);

    private final PaymentRepository paymentRepository;
    private final PaymentEventPublisher eventPublisher;

    public PaymentService(PaymentRepository paymentRepository, PaymentEventPublisher eventPublisher) {
        this.paymentRepository = paymentRepository;
        this.eventPublisher = eventPublisher;
    }

    @Transactional
    public PaymentResponse processPayment(CreatePaymentRequest request) {
        // Idempotency check - return existing payment if already processed
        if (request.idempotencyKey() != null) {
            Optional<Payment> existing = paymentRepository.findByIdempotencyKey(request.idempotencyKey());
            if (existing.isPresent()) {
                log.info("Returning existing payment for idempotency key: {}", request.idempotencyKey());
                return PaymentResponse.from(existing.get());
            }
        }

        Payment payment = new Payment();
        payment.setOrderId(request.orderId());
        payment.setAmount(request.amount());
        payment.setCurrency(request.currency() != null ? request.currency() : "USD");
        payment.setPaymentMethod(request.paymentMethod());
        payment.setIdempotencyKey(request.idempotencyKey());
        payment.setStatus(PaymentStatus.PENDING);

        Payment savedPayment = paymentRepository.save(payment);
        log.info("Created payment: {} for order: {}", savedPayment.getId(), savedPayment.getOrderId());

        // Simulate payment processing
        try {
            processPaymentWithProvider(savedPayment);
            savedPayment.setStatus(PaymentStatus.COMPLETED);
            savedPayment = paymentRepository.save(savedPayment);

            PaymentResponse response = PaymentResponse.from(savedPayment);
            eventPublisher.publishPaymentCompleted(response);
            log.info("Payment completed: {}", savedPayment.getId());

            return response;
        } catch (Exception e) {
            savedPayment.setStatus(PaymentStatus.FAILED);
            savedPayment = paymentRepository.save(savedPayment);

            PaymentResponse response = PaymentResponse.from(savedPayment);
            eventPublisher.publishPaymentFailed(response);
            log.error("Payment failed: {}", savedPayment.getId(), e);

            return response;
        }
    }

    @Transactional(readOnly = true)
    public PaymentResponse getPayment(UUID paymentId) {
        Payment payment = paymentRepository.findById(paymentId)
                .orElseThrow(() -> new PaymentNotFoundException(paymentId));
        return PaymentResponse.from(payment);
    }

    @Transactional
    public PaymentResponse refundPayment(UUID paymentId) {
        Payment payment = paymentRepository.findById(paymentId)
                .orElseThrow(() -> new PaymentNotFoundException(paymentId));

        if (payment.getStatus() == PaymentStatus.REFUNDED) {
            return PaymentResponse.from(payment);
        }

        if (payment.getStatus() != PaymentStatus.COMPLETED) {
            throw new IllegalStateException("Cannot refund payment in status: " + payment.getStatus());
        }

        // Simulate refund processing
        payment.setStatus(PaymentStatus.REFUNDED);
        Payment savedPayment = paymentRepository.save(payment);

        PaymentResponse response = PaymentResponse.from(savedPayment);
        eventPublisher.publishPaymentRefunded(response);
        log.info("Payment refunded: {}", paymentId);

        return response;
    }

    private void processPaymentWithProvider(Payment payment) {
        // Simulate payment provider call
        // In a real system, this would call Stripe, PayPal, etc.
        log.info("Processing payment {} with provider for amount: {} {}",
                payment.getId(), payment.getAmount(), payment.getCurrency());
    }

    public static class PaymentNotFoundException extends RuntimeException {
        public PaymentNotFoundException(UUID paymentId) {
            super("Payment not found: " + paymentId);
        }
    }
}
