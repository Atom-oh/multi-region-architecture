package routes

// GetRouteMap returns the mapping of API path prefixes to backend services
func GetRouteMap() map[string]string {
	return map[string]string{
		// Core Services
		"/api/v1/products":  "product-catalog.core-services.svc.cluster.local:80",
		"/api/v1/search":    "search.core-services.svc.cluster.local:80",
		"/api/v1/cart":      "cart.core-services.svc.cluster.local:80",
		"/api/v1/orders":    "order.core-services.svc.cluster.local:80",
		"/api/v1/payments":  "payment.core-services.svc.cluster.local:80",
		"/api/v1/inventory": "inventory.core-services.svc.cluster.local:80",

		// User Services
		"/api/v1/auth":      "user-account.user-services.svc.cluster.local:80",
		"/api/v1/profiles":  "user-profile.user-services.svc.cluster.local:80",
		"/api/v1/wishlists": "wishlist.user-services.svc.cluster.local:80",
		"/api/v1/reviews":   "review.user-services.svc.cluster.local:80",

		// Fulfillment Services
		"/api/v1/shipments":  "shipping.fulfillment.svc.cluster.local:80",
		"/api/v1/warehouses": "warehouse.fulfillment.svc.cluster.local:80",
		"/api/v1/returns":    "returns.fulfillment.svc.cluster.local:80",

		// Business Services
		"/api/v1/pricing":          "pricing.business-services.svc.cluster.local:80",
		"/api/v1/recommendations":  "recommendation.business-services.svc.cluster.local:80",
		"/api/v1/notifications":    "notification.business-services.svc.cluster.local:80",
		"/api/v1/sellers":          "seller.business-services.svc.cluster.local:80",

		// Platform Services
		"/api/v1/events":    "event-bus.platform.svc.cluster.local:80",
		"/api/v1/analytics": "analytics.platform.svc.cluster.local:80",
	}
}
