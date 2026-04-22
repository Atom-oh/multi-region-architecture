# Frontend — VELLURE Shopping Mall SPA

React 19 + Vite 8 + Tailwind CSS 4 single-page application. Korean-first e-commerce frontend for multi-region shopping mall.

## Commands

```bash
npm run dev       # Dev server with HMR (localhost:5173)
npm run build     # Production build → dist/
npm run preview   # Preview production build locally
npm run lint      # ESLint (flat config, react-hooks + react-refresh)
```

**Deploy**: `scripts/deploy-frontend.sh` from repo root — builds, uploads to S3, invalidates CloudFront (`E2XBVTVYBYX8T6`).

## Tech Stack

- **React 19** with JSX (no TypeScript)
- **Vite 8** with `@vitejs/plugin-react` (Oxc)
- **Tailwind CSS 4** via `@tailwindcss/vite` plugin (not PostCSS)
- **react-router-dom 7** for client-side routing
- **ESLint 9** flat config (`eslint.config.js`)

No state management library — uses React Context (`AuthContext`, `CartContext`, `I18nContext`). Provider nesting order in `App.jsx`: I18n > Auth > Cart (Cart depends on Auth for user ID).

## Project Structure

```
src/
  api.js              # API client (fetch wrapper), mapProduct/mapOrder helpers
  utils.js            # Validators (email, phone, password, card) + formatPrice
  App.jsx             # Router + context providers
  index.css           # Tailwind @import + design tokens (@theme)
  main.jsx            # React root entry
  pages/              # 14 route pages (one component per route)
  components/         # 8 shared components (Layout, Navbar, Footer, etc.)
  context/            # Auth, Cart, I18n providers
  i18n/translations.js # ko/en translation strings
  assets/             # Static images (hero, logos)
```

## Key Patterns

### API Layer (`api.js`)
- All backend calls go through `api(path, options)` which prefixes `/api/v1`
- Auto-adds trailing slash before query params (avoids 301 redirects from Go/Python backends)
- 401 responses auto-logout and redirect to `/login`
- `mapProduct(raw)` normalizes backend product documents to frontend shape: `id`, `name`, `price`, `originalPrice`, `images`, `description`, `brand`, `tags`, `attributes`, `stock`
- `mapOrder(raw)` normalizes order documents

### Design System
- **Brand**: VELLURE — warm amber/brown palette (`brand-500: #d88100`)
- **Tokens**: Defined in `index.css` `@theme` block — Material Design 3 inspired (surface, on-surface, outline variants)
- **Fonts**: Plus Jakarta Sans (headlines), Inter (body)
- **Icons**: Google Material Symbols Outlined (loaded via CDN in `index.html`)
- **Currency**: Always KRW (`₩`), formatted via `toLocaleString('ko-KR')`

### Authentication
- JWT token stored in `localStorage` as `access_token`
- User object stored in `localStorage` as `user`
- `ProtectedRoute` wraps routes requiring auth — redirects to `/login`
- `getToken()` exported from `AuthContext` for `api.js` header injection

### i18n
- Two languages: `ko` (default), `en`
- `useI18n()` hook returns `{ lang, t, toggleLang }`
- `t(key, params)` with `{param}` interpolation
- Language persisted in `localStorage`

### Routing
All routes defined in `App.jsx`. Public: `/login`, `/register`, `/products`, `/products/:id`. Protected (wrapped in `ProtectedRoute`): everything else.

## Non-Obvious Things

- **No test framework** — no unit or integration tests exist. Verify features manually in browser.
- **No TypeScript** — plain JSX throughout. `@types/react` in devDeps is for IDE support only.
- **Tailwind v4 config** — tokens live in `index.css` `@theme` block, NOT in `tailwind.config.js` (which doesn't exist). The Vite plugin handles everything.
- **formatPrice duplication** — `utils.js` exports `formatPrice` but most pages define their own inline copy. Both produce the same `₩X,XXX` format.
- **API trailing slash** — `api.js` auto-appends `/` before query strings. Backend routes without trailing slash support will 301; this avoids that.
- **Product images** — 1000 real products crawled from danuri.io. Images served from danuri.io CDN. `mapProduct` filters out `mall.example.com` placeholder URLs.
- **No build-time env vars** — API base is hardcoded as `/api/v1` (relies on reverse proxy in production).
- **Error handling** — pages use try/catch around `api()` calls. `api.js` throws `ApiError(status, message, data)`. 401 triggers auto-logout. Pages typically show `alert()` on error or set empty-state UI.
- **Checkout validation** — Card number, expiry, CVC validation removed for demo mode. Only shipping info (name, phone, address) is required. Card fields still render but are optional.
- **i18n gaps** — `OrderStatusBadge.jsx` hardcodes Korean strings instead of using `t()`. Other components use i18n correctly.
- **deploy-frontend.sh** — has placeholder `CF_DISTRIBUTION="EXXXXXXXXXXXXX"` — use actual ID `E2XBVTVYBYX8T6`.
