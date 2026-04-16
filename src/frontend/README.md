# VELLURE Shopping Mall — Frontend

React 19 SPA for the multi-region shopping mall platform. Korean-first e-commerce UI with bilingual (ko/en) support.

## Quick Start

```bash
npm install
npm run dev       # http://localhost:5173
```

In production, the app is served from S3 via CloudFront. API calls go to `/api/v1/*` which the API gateway routes to backend microservices.

## Stack

| Layer | Technology |
|-------|-----------|
| Framework | React 19 (JSX, no TS) |
| Build | Vite 8 |
| Styling | Tailwind CSS 4 (`@tailwindcss/vite`) |
| Routing | react-router-dom 7 |
| State | React Context (Auth, Cart, I18n) |
| Icons | Material Symbols Outlined (CDN) |
| Lint | ESLint 9 (flat config) |

## Project Structure

```
src/
  api.js              # Fetch wrapper + data mappers
  utils.js            # Validators + formatPrice
  App.jsx             # Routes + providers
  index.css           # Tailwind tokens (VELLURE design system)
  pages/              # 14 page components
  components/         # 8 shared components
  context/            # AuthContext, CartContext, I18nContext
  i18n/               # Korean/English translations
```

## Pages

| Route | Page | Auth |
|-------|------|------|
| `/` | HomePage | Yes |
| `/products` | ProductsPage (paginated, 20/page) | No |
| `/products/:id` | ProductDetailPage (gallery, tabs, reviews) | No |
| `/cart` | CartPage | Yes |
| `/checkout` | CheckoutPage | Yes |
| `/orders` | OrdersPage | Yes |
| `/orders/:id` | OrderDetailPage | Yes |
| `/profile` | ProfilePage | Yes |
| `/wishlist` | WishlistPage | Yes |
| `/notifications` | NotificationsPage | Yes |
| `/seller` | SellerDashboardPage | Yes |
| `/returns` | ReturnsPage | Yes |
| `/login` | LoginPage | No |
| `/register` | RegisterPage | No |

## Deploy

```bash
# From repo root
bash scripts/deploy-frontend.sh
```

Builds, uploads to S3, and invalidates CloudFront distribution.

## Design System

VELLURE Prime Horizon — warm amber brand palette on neutral surfaces. Material Design 3 token structure defined in `src/index.css` `@theme` block.
