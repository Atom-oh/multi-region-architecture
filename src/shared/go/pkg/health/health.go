package health

import (
	"net/http"
	"sync/atomic"

	"github.com/gin-gonic/gin"
)

type Checker struct {
	ready   atomic.Bool
	started atomic.Bool
}

func New() *Checker {
	return &Checker{}
}

func (c *Checker) SetReady(ready bool) {
	c.ready.Store(ready)
}

func (c *Checker) SetStarted(started bool) {
	c.started.Store(started)
}

func (c *Checker) RegisterRoutes(r *gin.Engine) {
	h := r.Group("/health")
	h.GET("/ready", c.readyHandler)
	h.GET("/live", c.liveHandler)
	h.GET("/startup", c.startupHandler)
}

func (c *Checker) readyHandler(ctx *gin.Context) {
	if c.ready.Load() {
		ctx.JSON(http.StatusOK, gin.H{"status": "ready"})
		return
	}
	ctx.JSON(http.StatusServiceUnavailable, gin.H{"status": "not_ready"})
}

func (c *Checker) liveHandler(ctx *gin.Context) {
	ctx.JSON(http.StatusOK, gin.H{"status": "alive"})
}

func (c *Checker) startupHandler(ctx *gin.Context) {
	if c.started.Load() {
		ctx.JSON(http.StatusOK, gin.H{"status": "started"})
		return
	}
	ctx.JSON(http.StatusServiceUnavailable, gin.H{"status": "starting"})
}
