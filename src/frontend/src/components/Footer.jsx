import { Link } from 'react-router-dom';

export default function Footer() {
  return (
    <footer className="bg-slate-800 text-slate-300">
      <div className="max-w-7xl mx-auto px-4 py-12">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-8">
          <div>
            <h3 className="text-white text-lg font-bold mb-4">Multi-Region Mall</h3>
            <p className="text-sm">
              글로벌 쇼핑의 새로운 기준.<br />
              전 세계 어디서나 빠르고 안정적인 쇼핑 경험을 제공합니다.
            </p>
          </div>

          <div>
            <h4 className="text-white font-semibold mb-4">쇼핑 안내</h4>
            <ul className="space-y-2 text-sm">
              <li><Link to="/products" className="hover:text-white transition-colors">전체 상품</Link></li>
              <li><Link to="/products?category=electronics" className="hover:text-white transition-colors">전자제품</Link></li>
              <li><Link to="/products?category=fashion" className="hover:text-white transition-colors">패션</Link></li>
              <li><Link to="/products?category=home" className="hover:text-white transition-colors">홈/리빙</Link></li>
            </ul>
          </div>

          <div>
            <h4 className="text-white font-semibold mb-4">고객 서비스</h4>
            <ul className="space-y-2 text-sm">
              <li><Link to="/orders" className="hover:text-white transition-colors">주문 조회</Link></li>
              <li><Link to="/returns" className="hover:text-white transition-colors">반품/교환</Link></li>
              <li><a href="#" className="hover:text-white transition-colors">자주 묻는 질문</a></li>
              <li><a href="#" className="hover:text-white transition-colors">1:1 문의</a></li>
            </ul>
          </div>

          <div>
            <h4 className="text-white font-semibold mb-4">고객센터</h4>
            <p className="text-2xl font-bold text-white mb-2">1588-0000</p>
            <p className="text-sm">
              평일 09:00 - 18:00<br />
              점심시간 12:00 - 13:00<br />
              주말/공휴일 휴무
            </p>
          </div>
        </div>

        <div className="border-t border-slate-700 mt-8 pt-8">
          <div className="flex flex-col md:flex-row justify-between items-center gap-4">
            <div className="text-sm text-slate-400">
              <p>(주)멀티리전몰 | 대표: 홍길동 | 사업자등록번호: 123-45-67890</p>
              <p>주소: 서울특별시 강남구 테헤란로 123, 멀티리전타워 10층</p>
            </div>
            <p className="text-sm text-slate-400">
              &copy; 2024 Multi-Region Mall. All rights reserved.
            </p>
          </div>
        </div>
      </div>
    </footer>
  );
}
