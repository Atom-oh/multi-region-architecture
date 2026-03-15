package com.mall.common.saga;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class SagaOrchestrator {

    private static final Logger log = LoggerFactory.getLogger(SagaOrchestrator.class);

    private final List<SagaStep> steps = new ArrayList<>();
    private final String sagaName;

    public SagaOrchestrator(String sagaName) {
        this.sagaName = sagaName;
    }

    public SagaOrchestrator addStep(SagaStep step) {
        steps.add(step);
        return this;
    }

    public void execute() throws SagaException {
        List<SagaStep> completed = new ArrayList<>();

        for (SagaStep step : steps) {
            try {
                log.info("Saga [{}] executing step: {}", sagaName, step.name());
                step.execute();
                completed.add(step);
            } catch (Exception e) {
                log.error("Saga [{}] step failed: {}", sagaName, step.name(), e);
                compensate(completed);
                throw new SagaException("Saga " + sagaName + " failed at step: " + step.name(), e);
            }
        }
        log.info("Saga [{}] completed successfully", sagaName);
    }

    private void compensate(List<SagaStep> completed) {
        List<SagaStep> reversed = new ArrayList<>(completed);
        Collections.reverse(reversed);

        for (SagaStep step : reversed) {
            try {
                log.info("Saga [{}] compensating step: {}", sagaName, step.name());
                step.compensate();
            } catch (Exception e) {
                log.error("Saga [{}] compensation failed for step: {}", sagaName, step.name(), e);
            }
        }
    }

    public interface SagaStep {
        String name();
        void execute() throws Exception;
        void compensate() throws Exception;
    }

    public static class SagaException extends Exception {
        public SagaException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
