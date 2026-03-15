package model

import (
	"errors"
	"time"
)

var ErrDLQMessageNotFound = errors.New("DLQ message not found")

type Event struct {
	ID         string      `json:"id"`
	Topic      string      `json:"topic"`
	Key        string      `json:"key"`
	Payload    interface{} `json:"payload"`
	Timestamp  time.Time   `json:"timestamp"`
	RetryCount int         `json:"retry_count"`
}

type DLQMessage struct {
	ID         string      `json:"id"`
	Topic      string      `json:"topic"`
	Key        string      `json:"key"`
	Payload    interface{} `json:"payload"`
	Error      string      `json:"error"`
	Timestamp  time.Time   `json:"timestamp"`
	RetryCount int         `json:"retry_count"`
}
