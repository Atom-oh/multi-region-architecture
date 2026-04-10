import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import { api } from '../api';
import { useI18n } from '../context/I18nContext';

const STEPS = [
  { key: 'ordered', icon: 'inventory_2' },
  { key: 'shipped', icon: 'package_2' },
  { key: 'outForDelivery', icon: 'local_shipping' },
  { key: 'delivered', icon: 'check_circle' },
];

function statusToStep(status) {
  switch (status) {
    case 'pending':
    case 'processing':
      return 1;
    case 'shipping':
    case 'shipped':
      return 2;
    case 'out_for_delivery':
      return 3;
    case 'delivered':
      return 4;
    default:
      return 0;
  }
}

export default function OrderDetailPage() {
  const { t } = useI18n();
  const { id } = useParams();
  const [order, setOrder] = useState(null);
  const [tracking, setTracking] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchOrder = async () => {
      try {
        const orderData = await api(`/orders/${id}`);
        const shippingAddr = orderData.shipping_address || {};
        const addressParts = [shippingAddr.city, shippingAddr.district, shippingAddr.street].filter(Boolean);
        setOrder({
          id: orderData.id,
          createdAt: orderData.created_at || orderData.createdAt,
          status: orderData.status,
          items: (orderData.items || []).map(i => ({
            productId: i.product_id || i.productId,
            name: i.name,
            quantity: i.quantity,
            price: i.price,
          })),
          subtotal: orderData.subtotal || orderData.total_amount,
          shippingFee: orderData.shipping_fee || 0,
          tax: orderData.tax || 0,
          total: orderData.total_amount || orderData.total,
          shipping: {
            name: shippingAddr.name || '',
            phone: shippingAddr.phone || '',
            address: addressParts.length > 0 ? addressParts.join(' ') : (shippingAddr.address || ''),
            addressDetail: shippingAddr.zip || shippingAddr.address_detail || '',
          },
          payment: {
            method: orderData.payment_method || t('checkout.card'),
            cardNumber: '**** **** **** 1234',
          },
          trackingNumber: orderData.tracking_number || '',
          carrier: orderData.carrier || '',
        });

        try {
          const shipData = await api(`/shipments/order/${id}`);
          const shipment = Array.isArray(shipData) ? shipData[0] : shipData;
          const events = (shipment?.events || shipment?.tracking_events || []).map(e => ({
            status: e.status,
            message: e.message || e.description,
            time: e.time || e.timestamp,
            completed: e.completed !== undefined ? e.completed : true,
          }));
          setTracking(events);
        } catch {
          setTracking([]);
        }
      } catch (error) {
        console.error('Failed to load order:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchOrder();
  }, [id]);

  const [cancelling, setCancelling] = useState(false);

  const handleCancelOrder = async () => {
    if (!window.confirm(t('orderDetail.cancelConfirm'))) return;
    setCancelling(true);
    try {
      await api(`/orders/${id}`, {
        method: 'PUT',
        body: JSON.stringify({ status: 'cancelled' }),
      });
      setOrder(prev => ({ ...prev, status: 'cancelled' }));
    } catch (err) {
      alert(err.message || t('orderDetail.cancelFailed'));
    } finally {
      setCancelling(false);
    }
  };

  const canCancel = order && (order.status === 'pending' || order.status === 'processing');

  const formatPrice = (price) => {
    if (price == null) return '';
    return `₩${Number(price).toLocaleString('ko-KR')}`;
  };

  const formatDate = (dateString) => {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-secondary text-lg">{t('common.loading')}</p>
      </div>
    );
  }

  if (!order) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-secondary text-lg">{t('orderDetail.notFound')}</p>
      </div>
    );
  }

  const currentStep = statusToStep(order.status);

  const estimatedDelivery = (() => {
    const d = new Date(order.createdAt);
    d.setDate(d.getDate() + 7);
    return d.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
  })();

  return (
    <div className="max-w-7xl mx-auto px-4 py-8">
      {/* Breadcrumb */}
      <nav className="text-sm text-secondary mb-6 flex items-center gap-2">
        <Link to="/" className="hover:text-brand-500 transition-colors">{t('nav.explore')}</Link>
        <span className="text-outline-variant">/</span>
        <Link to="/orders" className="hover:text-brand-500 transition-colors">{t('orders.title')}</Link>
        <span className="text-outline-variant">/</span>
        <span className="text-on-surface font-medium">{order.id}</span>
      </nav>

      {/* Order Header Card */}
      <div className="bg-white rounded-xl shadow-sm p-6 mb-8">
        <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
          <div>
            <h1 className="text-3xl font-extrabold text-on-surface font-[family-name:var(--font-headline)]">
              {t('orderDetail.orderNumber')} {order.id.slice(0, 8).toUpperCase()}
            </h1>
            <p className="text-secondary mt-1">
              {t('orderDetail.placedOn')} {formatDate(order.createdAt)}
            </p>
          </div>
          <div className="flex items-center gap-3 flex-shrink-0">
            <button className="inline-flex items-center gap-2 px-5 py-2.5 bg-brand-500 text-white rounded-lg font-semibold text-sm hover:bg-brand-600 transition-colors">
              <span className="material-symbols-outlined text-[18px]">local_shipping</span>
              {t('orderDetail.trackPackage')}
            </button>
            <button className="inline-flex items-center gap-2 px-5 py-2.5 bg-surface-high text-on-surface rounded-lg font-semibold text-sm hover:bg-surface-highest transition-colors">
              <span className="material-symbols-outlined text-[18px]">receipt_long</span>
              {t('orderDetail.viewInvoice')}
            </button>
            {canCancel && (
              <button
                onClick={handleCancelOrder}
                disabled={cancelling}
                className="inline-flex items-center gap-2 px-5 py-2.5 bg-red-50 text-red-600 border border-red-200 rounded-lg font-semibold text-sm hover:bg-red-100 transition-colors disabled:opacity-50"
              >
                <span className="material-symbols-outlined text-[18px]">cancel</span>
                {cancelling ? t('orderDetail.cancelling') : t('orderDetail.cancel')}
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Progress Stepper */}
      <div className="bg-white rounded-xl shadow-sm p-6 mb-8">
        <div className="flex items-center justify-between relative">
          {STEPS.map((step, idx) => {
            const stepNum = idx + 1;
            const isActive = stepNum <= currentStep;
            const isCompleted = stepNum < currentStep;
            return (
              <div key={step.key} className="flex flex-col items-center relative z-10 flex-1">
                {/* Connecting line (before this step) */}
                {idx > 0 && (
                  <div
                    className={`absolute top-5 right-1/2 w-full h-0.5 -z-10 ${
                      stepNum <= currentStep ? 'bg-brand-500' : 'bg-outline-variant'
                    }`}
                  />
                )}
                {/* Circle */}
                <div
                  className={`w-10 h-10 rounded-full flex items-center justify-center ${
                    isActive
                      ? 'bg-brand-500 text-white'
                      : 'bg-surface-high text-outline'
                  }`}
                >
                  <span
                    className="material-symbols-outlined text-[20px]"
                    style={isCompleted ? { fontVariationSettings: "'FILL' 1" } : undefined}
                  >
                    {step.icon}
                  </span>
                </div>
                {/* Label */}
                <span className={`text-xs mt-2 font-medium ${
                  isActive ? 'text-brand-500' : 'text-outline'
                }`}>
                  {t(`orderDetail.step.${step.key}`)}
                </span>
              </div>
            );
          })}
        </div>

        {/* Estimated Delivery Banner */}
        <div className="mt-6 bg-brand-300 rounded-lg px-4 py-3 flex items-center gap-3">
          <span className="material-symbols-outlined text-brand-700 text-[20px]" style={{ fontVariationSettings: "'FILL' 1" }}>
            calendar_today
          </span>
          <p className="text-sm font-medium text-brand-800">
            {t('orderDetail.estimatedDelivery')}: {estimatedDelivery}
          </p>
        </div>
      </div>

      {/* Bento Grid: 3 columns */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left 2 columns */}
        <div className="lg:col-span-2 space-y-6">
          {/* Order Items Card */}
          <div className="bg-white rounded-xl shadow-sm p-6">
            <h2 className="text-lg font-bold text-on-surface font-[family-name:var(--font-headline)] mb-4">
              {t('orderDetail.items')}
            </h2>
            <div className="divide-y divide-outline-variant/30">
              {order.items.map((item) => (
                <div key={item.productId} className="flex items-center gap-4 py-4 first:pt-0 last:pb-0">
                  <div className="w-24 h-24 bg-surface-low rounded-lg overflow-hidden flex-shrink-0">
                    <img
                      src={`https://picsum.photos/seed/${item.productId}/200/200`}
                      alt={item.name}
                      className="w-full h-full object-cover"
                    />
                  </div>
                  <div className="flex-1 min-w-0">
                    <Link
                      to={`/products/${item.productId}`}
                      className="font-semibold text-on-surface hover:text-brand-500 transition-colors"
                    >
                      {item.name}
                    </Link>
                    <p className="text-sm text-secondary mt-0.5">{t('common.qty')} {item.quantity}</p>
                    <p className="text-sm font-bold text-on-surface mt-1">
                      {formatPrice(item.price * item.quantity)}
                    </p>
                    <Link
                      to="/returns"
                      className="text-xs text-brand-500 hover:text-brand-600 font-medium mt-1 inline-block transition-colors"
                    >
                      {t('orderDetail.returnOrReplace')}
                    </Link>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Latest Tracking Update Card */}
          {tracking.length > 0 && (
            <div className="bg-white rounded-xl shadow-sm p-6">
              <h2 className="text-lg font-bold text-on-surface font-[family-name:var(--font-headline)] mb-4">
                {t('orderDetail.latestTracking')}
              </h2>
              {(order.carrier || order.trackingNumber) && (
                <div className="flex items-center gap-4 mb-5 p-3 bg-surface-low rounded-lg">
                  {order.carrier && (
                    <div>
                      <p className="text-xs text-secondary">{t('orderDetail.carrier')}</p>
                      <p className="font-medium text-on-surface text-sm">{order.carrier}</p>
                    </div>
                  )}
                  {order.trackingNumber && (
                    <div>
                      <p className="text-xs text-secondary">{t('orderDetail.trackingNumber')}</p>
                      <p className="font-medium text-on-surface text-sm">{order.trackingNumber}</p>
                    </div>
                  )}
                </div>
              )}

              <div className="relative">
                {tracking.map((step, index) => (
                  <div key={index} className="flex gap-4 pb-5 last:pb-0">
                    <div className="relative flex flex-col items-center">
                      <div
                        className={`w-3 h-3 rounded-full mt-1 ${
                          step.completed ? 'bg-brand-500' : 'bg-outline-variant'
                        }`}
                      />
                      {index < tracking.length - 1 && (
                        <div
                          className={`w-0.5 flex-1 mt-1 ${
                            step.completed ? 'bg-brand-500' : 'bg-outline-variant'
                          }`}
                        />
                      )}
                    </div>
                    <div className="flex-1 -mt-0.5">
                      <p className={`text-sm font-medium ${step.completed ? 'text-on-surface' : 'text-outline'}`}>
                        {step.message}
                      </p>
                      <p className="text-xs text-secondary mt-0.5">{step.time}</p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Right column */}
        <div className="space-y-6">
          {/* Shipping Address Card */}
          <div className="bg-white rounded-xl shadow-sm p-6">
            <h2 className="text-sm font-bold text-on-surface uppercase tracking-wider mb-3">
              {t('orderDetail.shippingInfo')}
            </h2>
            <div className="space-y-2 text-sm">
              <p className="font-semibold text-on-surface">{order.shipping.name || '-'}</p>
              <p className="text-secondary">{order.shipping.address || '-'}</p>
              {order.shipping.addressDetail && (
                <p className="text-secondary">{order.shipping.addressDetail}</p>
              )}
              <p className="text-secondary">{order.shipping.phone || '-'}</p>
            </div>
          </div>

          {/* Payment Method Card */}
          <div className="bg-white rounded-xl shadow-sm p-6">
            <h2 className="text-sm font-bold text-on-surface uppercase tracking-wider mb-3">
              {t('orderDetail.paymentInfo')}
            </h2>
            <div className="flex items-center gap-3">
              <div className="w-12 h-8 bg-blue-600 rounded flex items-center justify-center">
                <span className="text-white text-[10px] font-extrabold tracking-wider">VISA</span>
              </div>
              <div className="text-sm">
                <p className="font-medium text-on-surface">{order.payment.method}</p>
                <p className="text-secondary">{order.payment.cardNumber}</p>
              </div>
            </div>
          </div>

          {/* Order Summary Card */}
          <div className="bg-white rounded-xl shadow-sm p-6">
            <h2 className="text-sm font-bold text-on-surface uppercase tracking-wider mb-3">
              {t('orderDetail.orderSummary')}
            </h2>
            <div className="space-y-2 text-sm">
              <div className="flex justify-between text-secondary">
                <span>{t('checkout.subtotal')}</span>
                <span className="text-on-surface">{formatPrice(order.subtotal)}</span>
              </div>
              <div className="flex justify-between text-secondary">
                <span>{t('checkout.shippingFee')}</span>
                <span className="text-on-surface">
                  {order.shippingFee === 0 ? t('checkout.free') : formatPrice(order.shippingFee)}
                </span>
              </div>
              <div className="flex justify-between text-secondary">
                <span>{t('orderDetail.tax')}</span>
                <span className="text-on-surface">{formatPrice(order.tax)}</span>
              </div>
              <div className="border-t border-outline-variant/30 pt-2 mt-2 flex justify-between font-bold text-on-surface">
                <span>{t('checkout.total')}</span>
                <span className="text-brand-500">{formatPrice(order.total)}</span>
              </div>
            </div>
          </div>

          {/* VELLURE Protection Banner */}
          <div className="bg-brand-900 rounded-xl p-5 text-white">
            <div className="flex items-center gap-3 mb-2">
              <span
                className="material-symbols-outlined text-brand-400 text-[22px]"
                style={{ fontVariationSettings: "'FILL' 1" }}
              >
                verified_user
              </span>
              <h3 className="font-bold text-sm font-[family-name:var(--font-headline)]">
                {t('orderDetail.vellureProtection')}
              </h3>
            </div>
            <p className="text-white/60 text-xs leading-relaxed">
              {t('orderDetail.vellureProtectionDesc')}
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
