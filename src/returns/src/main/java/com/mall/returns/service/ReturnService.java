package com.mall.returns.service;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.mall.returns.dto.CreateReturnRequest;
import com.mall.returns.dto.ReturnResponse;
import com.mall.returns.event.ReturnEventPublisher;
import com.mall.returns.model.ReturnItem;
import com.mall.returns.model.ReturnRequest;
import com.mall.returns.model.ReturnStatus;
import com.mall.returns.repository.ReturnRequestRepository;

@Service
public class ReturnService {

    private static final Logger logger = LoggerFactory.getLogger(ReturnService.class);

    private final ReturnRequestRepository returnRequestRepository;
    private final ReturnEventPublisher eventPublisher;

    public ReturnService(ReturnRequestRepository returnRequestRepository, ReturnEventPublisher eventPublisher) {
        this.returnRequestRepository = returnRequestRepository;
        this.eventPublisher = eventPublisher;
    }

    @Transactional
    public ReturnResponse createReturn(CreateReturnRequest request) {
        ReturnRequest returnRequest = new ReturnRequest();
        returnRequest.setOrderId(request.orderId());
        returnRequest.setUserId(request.userId());
        returnRequest.setReason(request.reason());
        returnRequest.setStatus(ReturnStatus.PENDING);

        if (request.items() != null) {
            for (var itemReq : request.items()) {
                ReturnItem item = new ReturnItem();
                item.setProductId(itemReq.productId());
                item.setSku(itemReq.sku());
                item.setQuantity(itemReq.quantity());
                item.setReason(itemReq.reason());
                returnRequest.addItem(item);
            }
        }

        returnRequest = returnRequestRepository.save(returnRequest);
        logger.info("Created return request {} for order {}", returnRequest.getId(), returnRequest.getOrderId());

        eventPublisher.publishReturnCreated(returnRequest);

        return ReturnResponse.from(returnRequest);
    }

    public Optional<ReturnResponse> getReturn(UUID id) {
        return returnRequestRepository.findById(id)
                .map(ReturnResponse::from);
    }

    public List<ReturnResponse> getReturnsByUser(String userId) {
        return returnRequestRepository.findByUserId(userId).stream()
                .map(ReturnResponse::from)
                .toList();
    }

    @Transactional
    public Optional<ReturnResponse> approveReturn(UUID id) {
        return returnRequestRepository.findById(id)
                .map(returnRequest -> {
                    if (returnRequest.getStatus() != ReturnStatus.PENDING) {
                        throw new IllegalStateException("Return request is not in PENDING status");
                    }
                    returnRequest.setStatus(ReturnStatus.APPROVED);
                    returnRequest = returnRequestRepository.save(returnRequest);
                    logger.info("Approved return request {}", id);

                    eventPublisher.publishReturnApproved(returnRequest);

                    return ReturnResponse.from(returnRequest);
                });
    }

    @Transactional
    public Optional<ReturnResponse> rejectReturn(UUID id) {
        return returnRequestRepository.findById(id)
                .map(returnRequest -> {
                    if (returnRequest.getStatus() != ReturnStatus.PENDING) {
                        throw new IllegalStateException("Return request is not in PENDING status");
                    }
                    returnRequest.setStatus(ReturnStatus.REJECTED);
                    returnRequest = returnRequestRepository.save(returnRequest);
                    logger.info("Rejected return request {}", id);

                    eventPublisher.publishReturnRejected(returnRequest);

                    return ReturnResponse.from(returnRequest);
                });
    }
}
