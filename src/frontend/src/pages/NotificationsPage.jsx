import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { api } from '../api';

export default function NotificationsPage() {
  const { user } = useAuth();
  const [notifications, setNotifications] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchNotifications = async () => {
      try {
        const data = await api(`/notifications/${user.id}`);
        const notifs = (data.notifications || data || []).map(n => ({
          id: n.id || n._id,
          type: n.type,
          title: n.title,
          message: n.message,
          orderId: n.order_id || n.orderId,
          productId: n.product_id || n.productId,
          createdAt: n.created_at || n.createdAt,
          isRead: n.read !== undefined ? n.read : (n.is_read !== undefined ? n.is_read : (n.isRead || false)),
        }));
        setNotifications(notifs);
      } catch (error) {
        console.error('데이터를 불러올 수 없습니다:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchNotifications();
  }, [user?.id]);

  const formatDate = (dateString) => {
    const date = new Date(dateString);
    const now = new Date();
    const diff = now - date;
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    const hours = Math.floor(diff / (1000 * 60 * 60));
    const minutes = Math.floor(diff / (1000 * 60));

    if (minutes < 60) return `${minutes}분 전`;
    if (hours < 24) return `${hours}시간 전`;
    if (days < 7) return `${days}일 전`;

    return date.toLocaleDateString('ko-KR', {
      month: 'long',
      day: 'numeric',
    });
  };

  const getIcon = (type) => {
    switch (type) {
      case 'shipping':
        return (
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4" />
          </svg>
        );
      case 'promotion':
        return (
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v13m0-13V6a2 2 0 112 2h-2zm0 0V5.5A2.5 2.5 0 109.5 8H12zm-7 4h14M5 12a2 2 0 110-4h14a2 2 0 110 4M5 12v7a2 2 0 002 2h10a2 2 0 002-2v-7" />
          </svg>
        );
      case 'order':
        return (
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
          </svg>
        );
      case 'review':
        return (
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z" />
          </svg>
        );
      default:
        return (
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
          </svg>
        );
    }
  };

  const getIconBg = (type) => {
    switch (type) {
      case 'shipping':
        return 'bg-blue-100 text-blue-500';
      case 'promotion':
        return 'bg-purple-100 text-purple-500';
      case 'order':
        return 'bg-green-100 text-green-500';
      case 'review':
        return 'bg-yellow-100 text-yellow-500';
      default:
        return 'bg-slate-100 text-slate-500';
    }
  };

  const markAsRead = (notificationId) => {
    setNotifications(prev =>
      prev.map(n =>
        n.id === notificationId ? { ...n, isRead: true } : n
      )
    );
    // TODO: Persist read status to backend when endpoint is available
    // api(`/notifications/${notificationId}/read`, { method: 'PUT' }).catch(() => {});
  };

  const markAllAsRead = () => {
    setNotifications(prev =>
      prev.map(n => ({ ...n, isRead: true }))
    );
    // TODO: Persist read-all status to backend when endpoint is available
  };

  const unreadCount = notifications.filter(n => !n.isRead).length;

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-slate-500 text-lg">로딩 중...</p>
      </div>
    );
  }

  return (
    <div className="max-w-3xl mx-auto px-4 py-8">
      <div className="flex items-center justify-between mb-8">
        <div>
          <h1 className="text-3xl font-bold text-slate-800">알림</h1>
          {unreadCount > 0 && (
            <p className="text-slate-500 mt-1">읽지 않은 알림 {unreadCount}개</p>
          )}
        </div>
        {unreadCount > 0 && (
          <button
            onClick={markAllAsRead}
            className="text-blue-500 hover:text-blue-600 font-medium"
          >
            모두 읽음 처리
          </button>
        )}
      </div>

      {notifications.length === 0 ? (
        <div className="text-center py-16">
          <svg className="w-24 h-24 text-slate-300 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
          </svg>
          <p className="text-slate-500 text-lg">알림이 없습니다.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {notifications.map((notification) => (
            <div
              key={notification.id}
              onClick={() => markAsRead(notification.id)}
              className={`bg-white rounded-lg shadow-sm p-4 flex gap-4 cursor-pointer hover:shadow-md transition-shadow ${
                !notification.isRead ? 'border-l-4 border-blue-500' : ''
              }`}
            >
              <div className={`w-12 h-12 rounded-full flex items-center justify-center flex-shrink-0 ${getIconBg(notification.type)}`}>
                {getIcon(notification.type)}
              </div>

              <div className="flex-1 min-w-0">
                <div className="flex items-start justify-between gap-2">
                  <h3 className={`font-medium ${!notification.isRead ? 'text-slate-800' : 'text-slate-600'}`}>
                    {notification.title}
                  </h3>
                  <span className="text-sm text-slate-400 flex-shrink-0">
                    {formatDate(notification.createdAt)}
                  </span>
                </div>
                <p className="text-slate-500 text-sm mt-1">{notification.message}</p>

                {notification.orderId && (
                  <Link
                    to={`/orders/${notification.orderId}`}
                    className="inline-block mt-2 text-sm text-blue-500 hover:text-blue-600"
                  >
                    주문 상세 보기 →
                  </Link>
                )}
                {notification.productId && (
                  <Link
                    to={`/products/${notification.productId}`}
                    className="inline-block mt-2 text-sm text-blue-500 hover:text-blue-600"
                  >
                    상품 보기 →
                  </Link>
                )}
              </div>

              {!notification.isRead && (
                <div className="w-2 h-2 bg-blue-500 rounded-full flex-shrink-0 mt-2" />
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
